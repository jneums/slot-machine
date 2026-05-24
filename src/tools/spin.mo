import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Int "mo:base/Int";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Time "mo:base/Time";
import Map "mo:map/Map";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Option "mo:base/Option";

import ToolContext "ToolContext";

module {

  public func config() : McpTypes.Tool = {
    name = "spin";
    title = ?"Spin the Slot Machine";
    description = ?"Spin the 3-reel slot machine! Wager credits and try your luck. Uses ICP's raw_rand() for provably fair randomness. Bet between 1 and 100 credits.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("bet", Json.obj([
          ("type", Json.str("integer")),
          ("description", Json.str("Number of credits to wager (1-100)")),
          ("minimum", Json.int(1)),
          ("maximum", Json.int(100)),
        ])),
      ])),
      ("required", Json.arr([Json.str("bet")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("spinId", Json.obj([("type", Json.str("string"))])),
        ("reels", Json.obj([("type", Json.str("string")), ("description", Json.str("Emoji display of the 3 reels"))])),
        ("reelSymbols", Json.obj([
          ("type", Json.str("array")),
          ("items", Json.obj([("type", Json.str("string"))])),
          ("description", Json.str("Symbol names for each reel")),
        ])),
        ("payout", Json.obj([("type", Json.str("integer"))])),
        ("multiplier", Json.obj([("type", Json.str("integer"))])),
        ("balanceAfter", Json.obj([("type", Json.str("integer"))])),
        ("seed", Json.obj([("type", Json.str("string")), ("description", Json.str("Hex-encoded random seed for verification"))])),
        ("message", Json.obj([("type", Json.str("string"))])),
      ])),
    ]);
  };

  // Convert 4 bytes (big-endian) to Nat
  func bytes4ToNat(b0 : Nat8, b1 : Nat8, b2 : Nat8, b3 : Nat8) : Nat {
    let n0 = Nat8.toNat(b0);
    let n1 = Nat8.toNat(b1);
    let n2 = Nat8.toNat(b2);
    let n3 = Nat8.toNat(b3);
    (n0 * 16_777_216) + (n1 * 65_536) + (n2 * 256) + n3;
  };

  // Convert blob to hex string
  func blobToHex(b : Blob) : Text {
    let bytes = Blob.toArray(b);
    var hex = "";
    for (byte in bytes.vals()) {
      let hi = Nat8.toNat(byte / 16);
      let lo = Nat8.toNat(byte % 16);
      hex #= hexChar(hi) # hexChar(lo);
    };
    hex;
  };

  func hexChar(n : Nat) : Text {
    switch (n) {
      case 0 { "0" }; case 1 { "1" }; case 2 { "2" }; case 3 { "3" };
      case 4 { "4" }; case 5 { "5" }; case 6 { "6" }; case 7 { "7" };
      case 8 { "8" }; case 9 { "9" }; case 10 { "a" }; case 11 { "b" };
      case 12 { "c" }; case 13 { "d" }; case 14 { "e" }; case 15 { "f" };
      case _ { "?" };
    };
  };

  // Derive 3 reel symbols from random seed
  public func seedToReels(seed : Blob) : [ToolContext.Symbol] {
    let bytes = Blob.toArray(seed);
    // Reel 0: bytes 0-3, Reel 1: bytes 4-7, Reel 2: bytes 8-11
    let v0 = bytes4ToNat(bytes[0], bytes[1], bytes[2], bytes[3]) % 100;
    let v1 = bytes4ToNat(bytes[4], bytes[5], bytes[6], bytes[7]) % 100;
    let v2 = bytes4ToNat(bytes[8], bytes[9], bytes[10], bytes[11]) % 100;
    [
      ToolContext.valueToSymbol(v0),
      ToolContext.valueToSymbol(v1),
      ToolContext.valueToSymbol(v2),
    ];
  };

  func getPayoutMessage(reels : [ToolContext.Symbol], multiplier : Nat, payout : Nat, bet : Nat) : Text {
    let reelStr = ToolContext.symbolToText(reels[0]) # " " # ToolContext.symbolToText(reels[1]) # " " # ToolContext.symbolToText(reels[2]);
    if (multiplier >= 100) {
      reelStr # " — 🎰 JACKPOT! " # Nat.toText(multiplier) # "x payout! You won " # Nat.toText(payout) # " credits! 🎰🎰🎰";
    } else if (multiplier >= 25) {
      reelStr # " — 💎 BIG WIN! " # Nat.toText(multiplier) # "x payout! You won " # Nat.toText(payout) # " credits! 💰💰💰";
    } else if (multiplier >= 3) {
      reelStr # " — 🎉 Three of a kind! " # Nat.toText(multiplier) # "x payout! You won " # Nat.toText(payout) # " credits!";
    } else if (multiplier == 1) {
      reelStr # " — Pair! You get your " # Nat.toText(bet) # " credits back.";
    } else {
      reelStr # " — No match. You lost " # Nat.toText(bet) # " credits.";
    };
  };

  public func handle(context : ToolContext.ToolContext) : (
    _args : McpTypes.JsonValue,
    _auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()
  ) -> async () {
    func(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      // Require auth
      let caller = switch (auth) {
        case (?a) { a.principal };
        case (null) { return ToolContext.makeError("UNAUTHORIZED: Authentication required to spin.", cb) };
      };

      // Parse bet
      let bet : Nat = switch (Result.toOption(Json.getAsNat(args, "bet"))) {
        case (?b) { b };
        case (null) {
          return ToolContext.makeError("INVALID_INPUT: Missing or invalid 'bet' parameter. Must be an integer 1-100.", cb);
        };
      };

      if (bet < ToolContext.MIN_BET or bet > ToolContext.MAX_BET) {
        return ToolContext.makeError("INVALID_INPUT: Bet must be between " # Nat.toText(ToolContext.MIN_BET) # " and " # Nat.toText(ToolContext.MAX_BET) # " credits.", cb);
      };

      // Get account
      let account = switch (Map.get(context.accounts, Map.phash, caller)) {
        case (?a) { a };
        case (null) {
          return ToolContext.makeError("NOT_FOUND: No account found. Use claim_faucet first to create an account and get free credits.", cb);
        };
      };

      // Check balance
      if (account.balance < bet) {
        return ToolContext.makeError("INSUFFICIENT_BALANCE: You have " # Nat.toText(account.balance) # " credits but tried to bet " # Nat.toText(bet) # ". Use claim_faucet to get more credits.", cb);
      };

      // Deduct bet
      account.balance -= bet;

      // Get random seed
      let seed = await context.getRandom();

      // Derive reels
      let reels = seedToReels(seed);

      // Calculate payout
      let multiplier = ToolContext.getMultiplier(reels);
      let payout = bet * multiplier;

      // Credit payout
      account.balance += payout;

      // Update player stats
      account.totalSpins += 1;
      account.totalWagered += bet;
      account.totalWon += payout;
      if (payout > account.biggestWin) {
        account.biggestWin := payout;
      };

      // Update machine stats
      context.machineStats.totalSpins += 1;
      context.machineStats.totalWagered += bet;
      context.machineStats.totalPaidOut += payout;

      // Store spin result
      context.spinCounter.count += 1;
      let spinId = "spin-" # Nat.toText(context.spinCounter.count);
      let now = Int.abs(Time.now());

      let spinResult : ToolContext.SpinResult = {
        id = spinId;
        player = caller;
        bet = bet;
        reels = reels;
        payout = payout;
        multiplier = multiplier;
        seed = seed;
        timestamp = now;
      };
      Map.set(context.spins, Map.thash, spinId, spinResult);

      // Add to player's spin history
      let existing = Option.get(Map.get(context.playerSpins, Map.phash, caller), ([] : [Text]));
      Map.set(context.playerSpins, Map.phash, caller, Array.append([spinId], existing));

      // Build response
      let message = getPayoutMessage(reels, multiplier, payout, bet);
      let reelDisplay = ToolContext.symbolToText(reels[0]) # " " # ToolContext.symbolToText(reels[1]) # " " # ToolContext.symbolToText(reels[2]);

      ToolContext.makeSuccess(Json.obj([
        ("spinId", Json.str(spinId)),
        ("reels", Json.str(reelDisplay)),
        ("reelSymbols", Json.arr([
          Json.str(ToolContext.symbolToName(reels[0])),
          Json.str(ToolContext.symbolToName(reels[1])),
          Json.str(ToolContext.symbolToName(reels[2])),
        ])),
        ("payout", Json.int(payout)),
        ("multiplier", Json.int(multiplier)),
        ("balanceAfter", Json.int(account.balance)),
        ("seed", Json.str(blobToHex(seed))),
        ("message", Json.str(message)),
      ]), cb);
    };
  };
};
