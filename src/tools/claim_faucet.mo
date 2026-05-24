import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Int "mo:base/Int";
import Time "mo:base/Time";
import Nat "mo:base/Nat";
import Map "mo:map/Map";

import ToolContext "ToolContext";

module {

  public func config() : McpTypes.Tool = {
    name = "claim_faucet";
    title = ?"Credit Faucet";
    description = ?"Claim free credits to play the slot machine. Grants 100 credits, available once every 4 hours. Creates your account on first claim.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("balance", Json.obj([
          ("type", Json.str("integer")),
          ("description", Json.str("Your current credit balance after claiming")),
        ])),
        ("claimed", Json.obj([
          ("type", Json.str("integer")),
          ("description", Json.str("Number of credits claimed")),
        ])),
        ("nextClaimAt", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("When you can next claim (timestamp nanos or 'now')")),
        ])),
        ("message", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("Human-readable status message")),
        ])),
      ])),
      ("required", Json.arr([Json.str("balance"), Json.str("claimed"), Json.str("nextClaimAt"), Json.str("message")])),
    ]);
  };

  public func handle(context : ToolContext.ToolContext) : (
    _args : McpTypes.JsonValue,
    _auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()
  ) -> async () {
    func(_args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      // Require authentication
      let caller = switch (auth) {
        case (?a) { a.principal };
        case (null) { return ToolContext.makeError("UNAUTHORIZED: Authentication required to claim faucet.", cb) };
      };

      let now = Int.abs(Time.now());

      switch (Map.get(context.accounts, Map.phash, caller)) {
        case (?account) {
          // Existing account — check cooldown
          let elapsed = now - account.lastFaucetClaim;
          if (elapsed < ToolContext.FAUCET_COOLDOWN_NANOS) {
            let remaining = ToolContext.FAUCET_COOLDOWN_NANOS - elapsed;
            let remainingHours = remaining / 3_600_000_000_000;
            let remainingMins = (remaining % 3_600_000_000_000) / 60_000_000_000;
            let nextClaimAt = account.lastFaucetClaim + ToolContext.FAUCET_COOLDOWN_NANOS;
            return ToolContext.makeSuccess(Json.obj([
              ("balance", Json.int(account.balance)),
              ("claimed", Json.int(0)),
              ("nextClaimAt", Json.str(Nat.toText(nextClaimAt))),
              ("message", Json.str("RATE_LIMITED: You already claimed recently. Next claim available in " # Nat.toText(remainingHours) # "h " # Nat.toText(remainingMins) # "m.")),
            ]), cb);
          };

          // Claim
          account.balance += ToolContext.FAUCET_AMOUNT;
          account.lastFaucetClaim := now;

          // Track peak balance
          if (account.balance > account.peakBalance) {
            account.peakBalance := account.balance;
          };

          ToolContext.makeSuccess(Json.obj([
            ("balance", Json.int(account.balance)),
            ("claimed", Json.int(ToolContext.FAUCET_AMOUNT)),
            ("nextClaimAt", Json.str(Nat.toText(now + ToolContext.FAUCET_COOLDOWN_NANOS))),
            ("message", Json.str("💰 Claimed " # Nat.toText(ToolContext.FAUCET_AMOUNT) # " credits! Balance: " # Nat.toText(account.balance))),
          ]), cb);
        };
        case (null) {
          // New account
          let account : ToolContext.PlayerAccount = {
            var balance = ToolContext.FAUCET_AMOUNT;
            var totalSpins = 0;
            var totalWagered = 0;
            var totalWon = 0;
            var biggestWin = 0;
            var peakBalance = ToolContext.FAUCET_AMOUNT;
            var lastFaucetClaim = now;
            createdAt = now;
          };
          Map.set(context.accounts, Map.phash, caller, account);
          context.machineStats.totalPlayers += 1;

          ToolContext.makeSuccess(Json.obj([
            ("balance", Json.int(ToolContext.FAUCET_AMOUNT)),
            ("claimed", Json.int(ToolContext.FAUCET_AMOUNT)),
            ("nextClaimAt", Json.str(Nat.toText(now + ToolContext.FAUCET_COOLDOWN_NANOS))),
            ("message", Json.str("🎰 Welcome! Account created with " # Nat.toText(ToolContext.FAUCET_AMOUNT) # " free credits. Good luck!")),
          ]), cb);
        };
      };
    };
  };
};
