import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Nat "mo:base/Nat";

import ToolContext "ToolContext";

module {

  public func config() : McpTypes.Tool = {
    name = "get_machine_stats";
    title = ?"Machine Statistics";
    description = ?"View global slot machine statistics including total spins, payouts, player count, and the full payout table. Public — no authentication required.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("totalSpins", Json.obj([("type", Json.str("integer"))])),
        ("totalWagered", Json.obj([("type", Json.str("integer"))])),
        ("totalPaidOut", Json.obj([("type", Json.str("integer"))])),
        ("totalPlayers", Json.obj([("type", Json.str("integer"))])),
        ("houseProfit", Json.obj([("type", Json.str("integer"))])),
        ("payoutTable", Json.obj([("type", Json.str("array")), ("items", Json.obj([("type", Json.str("object"))]))])),
      ])),
    ]);
  };

  public func handle(context : ToolContext.ToolContext) : (
    _args : McpTypes.JsonValue,
    _auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()
  ) -> async () {
    func(_args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      let stats = context.machineStats;

      let houseProfitInt : Int = stats.totalWagered - stats.totalPaidOut;
      let houseProfit : Json.Json = Json.int(houseProfitInt);

      let payoutTable = Json.arr([
        Json.obj([
          ("combo", Json.str("🎰🎰🎰")),
          ("name", Json.str("Three Sevens")),
          ("multiplier", Json.str("100x")),
          ("description", Json.str("JACKPOT!")),
        ]),
        Json.obj([
          ("combo", Json.str("💎💎💎")),
          ("name", Json.str("Three Diamonds")),
          ("multiplier", Json.str("50x")),
          ("description", Json.str("Diamond Rush")),
        ]),
        Json.obj([
          ("combo", Json.str("⭐⭐⭐")),
          ("name", Json.str("Three Stars")),
          ("multiplier", Json.str("25x")),
          ("description", Json.str("Star Align")),
        ]),
        Json.obj([
          ("combo", Json.str("🔔🔔🔔")),
          ("name", Json.str("Three Bells")),
          ("multiplier", Json.str("10x")),
          ("description", Json.str("Bell Ringer")),
        ]),
        Json.obj([
          ("combo", Json.str("🍋🍋🍋")),
          ("name", Json.str("Three Lemons")),
          ("multiplier", Json.str("5x")),
          ("description", Json.str("Lemon Squeeze")),
        ]),
        Json.obj([
          ("combo", Json.str("🍒🍒🍒")),
          ("name", Json.str("Three Cherries")),
          ("multiplier", Json.str("3x")),
          ("description", Json.str("Cherry Bomb")),
        ]),
        Json.obj([
          ("combo", Json.str("Any Pair")),
          ("name", Json.str("Pair")),
          ("multiplier", Json.str("1x")),
          ("description", Json.str("Push — get your bet back")),
        ]),
        Json.obj([
          ("combo", Json.str("No Match")),
          ("name", Json.str("Loss")),
          ("multiplier", Json.str("0x")),
          ("description", Json.str("Better luck next time")),
        ]),
      ]);

      let symbolWeights = Json.arr([
        Json.obj([("symbol", Json.str("🍒 Cherry")), ("weight", Json.str("25%"))]),
        Json.obj([("symbol", Json.str("🍋 Lemon")), ("weight", Json.str("25%"))]),
        Json.obj([("symbol", Json.str("🔔 Bell")), ("weight", Json.str("20%"))]),
        Json.obj([("symbol", Json.str("⭐ Star")), ("weight", Json.str("15%"))]),
        Json.obj([("symbol", Json.str("💎 Diamond")), ("weight", Json.str("10%"))]),
        Json.obj([("symbol", Json.str("🎰 Seven")), ("weight", Json.str("5%"))]),
      ]);

      ToolContext.makeSuccess(Json.obj([
        ("totalSpins", Json.int(stats.totalSpins)),
        ("totalWagered", Json.int(stats.totalWagered)),
        ("totalPaidOut", Json.int(stats.totalPaidOut)),
        ("totalPlayers", Json.int(stats.totalPlayers)),
        ("houseProfit", houseProfit),
        ("betRange", Json.obj([
          ("min", Json.int(ToolContext.MIN_BET)),
          ("max", Json.int(ToolContext.MAX_BET)),
        ])),
        ("faucetAmount", Json.int(ToolContext.FAUCET_AMOUNT)),
        ("payoutTable", payoutTable),
        ("symbolWeights", symbolWeights),
        ("randomnessSource", Json.str("ICP raw_rand() — subnet threshold BLS signature, cryptographically random and verifiable")),
      ]), cb);
    };
  };
};
