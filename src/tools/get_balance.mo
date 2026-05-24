import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Nat "mo:base/Nat";
import Map "mo:map/Map";

import ToolContext "ToolContext";

module {

  public func config() : McpTypes.Tool = {
    name = "get_balance";
    title = ?"Check Balance";
    description = ?"Check your current credit balance and lifetime statistics.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("balance", Json.obj([("type", Json.str("integer")), ("description", Json.str("Current credit balance"))])),
        ("totalSpins", Json.obj([("type", Json.str("integer"))])),
        ("totalWagered", Json.obj([("type", Json.str("integer"))])),
        ("totalWon", Json.obj([("type", Json.str("integer"))])),
        ("biggestWin", Json.obj([("type", Json.str("integer"))])),
        ("netProfit", Json.obj([("type", Json.str("integer")), ("description", Json.str("Total won minus total wagered"))])),
      ])),
    ]);
  };

  public func handle(context : ToolContext.ToolContext) : (
    _args : McpTypes.JsonValue,
    _auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()
  ) -> async () {
    func(_args : McpTypes.JsonValue, auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      let caller = switch (auth) {
        case (?a) { a.principal };
        case (null) { return ToolContext.makeError("UNAUTHORIZED: Authentication required.", cb) };
      };

      let account = switch (Map.get(context.accounts, Map.phash, caller)) {
        case (?a) { a };
        case (null) {
          return ToolContext.makeError("NOT_FOUND: No account found. Use claim_faucet first.", cb);
        };
      };

      // Calculate net profit (can be negative, but Nat can't be negative, so handle with two fields)
      let netProfit : Int = account.totalWon - account.totalWagered;
      let netProfitDisplay : Json.Json = Json.int(netProfit);

      ToolContext.makeSuccess(Json.obj([
        ("balance", Json.int(account.balance)),
        ("totalSpins", Json.int(account.totalSpins)),
        ("totalWagered", Json.int(account.totalWagered)),
        ("totalWon", Json.int(account.totalWon)),
        ("biggestWin", Json.int(account.biggestWin)),
        ("netProfit", netProfitDisplay),
      ]), cb);
    };
  };
};
