import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Nat "mo:base/Nat";
import Map "mo:map/Map";
import Array "mo:base/Array";
import Option "mo:base/Option";

import ToolContext "ToolContext";

module {

  public func config() : McpTypes.Tool = {
    name = "get_spin_history";
    title = ?"Spin History";
    description = ?"View your past spin results including reels, bets, payouts, and seeds for verification.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("limit", Json.obj([
          ("type", Json.str("integer")),
          ("description", Json.str("Max results to return (default: 20, max: 100)")),
          ("minimum", Json.int(1)),
          ("maximum", Json.int(100)),
        ])),
        ("offset", Json.obj([
          ("type", Json.str("integer")),
          ("description", Json.str("Number of results to skip (default: 0)")),
          ("minimum", Json.int(0)),
        ])),
      ])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("spins", Json.obj([
          ("type", Json.str("array")),
          ("items", Json.obj([("type", Json.str("object"))])),
        ])),
        ("total", Json.obj([("type", Json.str("integer"))])),
        ("showing", Json.obj([("type", Json.str("integer"))])),
      ])),
    ]);
  };

  public func handle(context : ToolContext.ToolContext) : (
    _args : McpTypes.JsonValue,
    _auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()
  ) -> async () {
    func(args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      let caller = switch (auth) {
        case (?a) { a.principal };
        case (null) { return ToolContext.makeError("UNAUTHORIZED: Authentication required.", cb) };
      };

      let limit = switch (Result.toOption(Json.getAsNat(args, "limit"))) {
        case (?l) { if (l > 100) { 100 } else if (l < 1) { 1 } else { l } };
        case (null) { 20 };
      };

      let offset = switch (Result.toOption(Json.getAsNat(args, "offset"))) {
        case (?o) { o };
        case (null) { 0 };
      };

      let spinIds = Option.get(Map.get(context.playerSpins, Map.phash, caller), ([] : [Text]));
      let total = spinIds.size();

      // spinIds are stored most-recent-first
      var results : [Json.Json] = [];
      var i = offset;
      var count = 0;
      while (i < total and count < limit) {
        let spinId = spinIds[i];
        switch (Map.get(context.spins, Map.thash, spinId)) {
          case (?spin) {
            let reelDisplay = ToolContext.symbolToText(spin.reels[0]) # " " # ToolContext.symbolToText(spin.reels[1]) # " " # ToolContext.symbolToText(spin.reels[2]);
            results := Array.append(results, [Json.obj([
              ("spinId", Json.str(spin.id)),
              ("bet", Json.int(spin.bet)),
              ("reels", Json.str(reelDisplay)),
              ("reelSymbols", Json.arr([
                Json.str(ToolContext.symbolToName(spin.reels[0])),
                Json.str(ToolContext.symbolToName(spin.reels[1])),
                Json.str(ToolContext.symbolToName(spin.reels[2])),
              ])),
              ("payout", Json.int(spin.payout)),
              ("multiplier", Json.int(spin.multiplier)),
              ("timestamp", Json.int(spin.timestamp)),
            ])]);
          };
          case (null) {};
        };
        i += 1;
        count += 1;
      };

      ToolContext.makeSuccess(Json.obj([
        ("spins", Json.arr(results)),
        ("total", Json.int(total)),
        ("showing", Json.int(count)),
      ]), cb);
    };
  };
};
