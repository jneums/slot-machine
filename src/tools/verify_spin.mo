import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Nat "mo:base/Nat";
import Nat8 "mo:base/Nat8";
import Map "mo:map/Map";
import Blob "mo:base/Blob";
import Principal "mo:base/Principal";

import ToolContext "ToolContext";
import Spin "spin";

module {

  public func config() : McpTypes.Tool = {
    name = "verify_spin";
    title = ?"Verify Spin Fairness";
    description = ?"Verify that any spin result was fairly generated. Re-derives the reel outcomes from the stored random seed and confirms they match. Public — no authentication required.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("spinId", Json.obj([
          ("type", Json.str("string")),
          ("description", Json.str("The spin ID to verify (e.g., 'spin-1')")),
        ])),
      ])),
      ("required", Json.arr([Json.str("spinId")])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("spinId", Json.obj([("type", Json.str("string"))])),
        ("player", Json.obj([("type", Json.str("string"))])),
        ("bet", Json.obj([("type", Json.str("integer"))])),
        ("seed", Json.obj([("type", Json.str("string")), ("description", Json.str("Hex-encoded random seed from raw_rand()"))])),
        ("recordedReels", Json.obj([("type", Json.str("string"))])),
        ("derivedReels", Json.obj([("type", Json.str("string")), ("description", Json.str("Reels re-derived from seed — should match recordedReels"))])),
        ("payout", Json.obj([("type", Json.str("integer"))])),
        ("multiplier", Json.obj([("type", Json.str("integer"))])),
        ("verified", Json.obj([("type", Json.str("boolean"))])),
        ("algorithm", Json.obj([("type", Json.str("string")), ("description", Json.str("Description of the seed-to-reel mapping algorithm"))])),
      ])),
    ]);
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

  func reelsToDisplay(reels : [ToolContext.Symbol]) : Text {
    ToolContext.symbolToText(reels[0]) # " " # ToolContext.symbolToText(reels[1]) # " " # ToolContext.symbolToText(reels[2]);
  };

  public func handle(context : ToolContext.ToolContext) : (
    _args : McpTypes.JsonValue,
    _auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()
  ) -> async () {
    func(args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      let spinId = switch (Result.toOption(Json.getAsText(args, "spinId"))) {
        case (?id) { id };
        case (null) {
          return ToolContext.makeError("INVALID_INPUT: Missing 'spinId' parameter.", cb);
        };
      };

      let spin = switch (Map.get(context.spins, Map.thash, spinId)) {
        case (?s) { s };
        case (null) {
          return ToolContext.makeError("NOT_FOUND: Spin '" # spinId # "' not found.", cb);
        };
      };

      // Re-derive reels from seed
      let derivedReels = Spin.seedToReels(spin.seed);
      let derivedMultiplier = ToolContext.getMultiplier(derivedReels);

      // Check if derived matches recorded
      let reelsMatch = ToolContext.symbolsEqual(spin.reels[0], derivedReels[0])
        and ToolContext.symbolsEqual(spin.reels[1], derivedReels[1])
        and ToolContext.symbolsEqual(spin.reels[2], derivedReels[2]);
      let payoutMatch = derivedMultiplier == spin.multiplier;
      let verified = reelsMatch and payoutMatch;

      let algorithm = "For each of 3 reels: take 4 bytes from seed (reel 0: bytes 0-3, reel 1: bytes 4-7, reel 2: bytes 8-11), convert to Nat32 big-endian, mod 100. Map: 0-24=cherry, 25-49=lemon, 50-69=bell, 70-84=star, 85-94=diamond, 95-99=seven. Seed source: ICP raw_rand() (subnet threshold BLS).";

      ToolContext.makeSuccess(Json.obj([
        ("spinId", Json.str(spin.id)),
        ("player", Json.str(Principal.toText(spin.player))),
        ("bet", Json.int(spin.bet)),
        ("seed", Json.str(blobToHex(spin.seed))),
        ("recordedReels", Json.str(reelsToDisplay(spin.reels))),
        ("derivedReels", Json.str(reelsToDisplay(derivedReels))),
        ("payout", Json.int(spin.payout)),
        ("multiplier", Json.int(spin.multiplier)),
        ("verified", Json.bool(verified)),
        ("algorithm", Json.str(algorithm)),
      ]), cb);
    };
  };
};
