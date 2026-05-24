import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import AuthTypes "mo:mcp-motoko-sdk/auth/Types";
import Result "mo:base/Result";
import Json "mo:json";
import Nat "mo:base/Nat";
import Principal "mo:base/Principal";
import Map "mo:map/Map";
import Array "mo:base/Array";
import Option "mo:base/Option";

import ToolContext "ToolContext";

module {

  public func config() : McpTypes.Tool = {
    name = "get_leaderboard";
    title = ?"Leaderboard";
    description = ?"View the slot machine leaderboard — biggest single win, most spins, highest balance ever, luckiest players, and all-time records. Public — no authentication required.";
    payment = null;
    inputSchema = Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("limit", Json.obj([
          ("type", Json.str("integer")),
          ("description", Json.str("Max players to show per category (default: 10, max: 50)")),
          ("minimum", Json.int(1)),
          ("maximum", Json.int(50)),
        ])),
      ])),
    ]);
    outputSchema = ?Json.obj([
      ("type", Json.str("object")),
      ("properties", Json.obj([
        ("biggestWins", Json.obj([("type", Json.str("array")), ("description", Json.str("Players ranked by biggest single win"))])),
        ("mostSpins", Json.obj([("type", Json.str("array")), ("description", Json.str("Players ranked by total spins"))])),
        ("highestBalances", Json.obj([("type", Json.str("array")), ("description", Json.str("Players ranked by peak balance achieved"))])),
        ("mostWagered", Json.obj([("type", Json.str("array")), ("description", Json.str("Players ranked by total credits wagered"))])),
        ("allTimeRecords", Json.obj([("type", Json.str("object")), ("description", Json.str("Machine-wide all-time records"))])),
      ])),
    ]);
  };

  public func handle(context : ToolContext.ToolContext) : (
    _args : McpTypes.JsonValue,
    _auth : ?AuthTypes.AuthInfo,
    cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()
  ) -> async () {
    func(args : McpTypes.JsonValue, _auth : ?AuthTypes.AuthInfo, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) : async () {

      let limit = switch (Result.toOption(Json.getAsNat(args, "limit"))) {
        case (?l) { if (l > 50) { 50 } else if (l < 1) { 1 } else { l } };
        case (null) { 10 };
      };

      // Collect all players into an array for sorting
      type PlayerEntry = {
        principal : Principal;
        account : ToolContext.PlayerAccount;
      };

      var players : [PlayerEntry] = [];
      for ((p, a) in Map.entries(context.accounts)) {
        players := Array.append(players, [{ principal = p; account = a }]);
      };

      // Biggest single win leaderboard
      let sortedByBiggestWin = Array.sort<PlayerEntry>(players, func(a, b) {
        if (a.account.biggestWin > b.account.biggestWin) { #less }
        else if (a.account.biggestWin < b.account.biggestWin) { #greater }
        else { #equal };
      });
      var biggestWins : [Json.Json] = [];
      var rank : Nat = 1;
      for (entry in sortedByBiggestWin.vals()) {
        if (rank <= limit and entry.account.biggestWin > 0) {
          biggestWins := Array.append(biggestWins, [Json.obj([
            ("rank", Json.int(rank)),
            ("player", Json.str(Principal.toText(entry.principal))),
            ("biggestWin", Json.int(entry.account.biggestWin)),
            ("totalSpins", Json.int(entry.account.totalSpins)),
          ])]);
          rank += 1;
        };
      };

      // Most spins leaderboard
      let sortedBySpins = Array.sort<PlayerEntry>(players, func(a, b) {
        if (a.account.totalSpins > b.account.totalSpins) { #less }
        else if (a.account.totalSpins < b.account.totalSpins) { #greater }
        else { #equal };
      });
      var mostSpins : [Json.Json] = [];
      rank := 1;
      for (entry in sortedBySpins.vals()) {
        if (rank <= limit and entry.account.totalSpins > 0) {
          mostSpins := Array.append(mostSpins, [Json.obj([
            ("rank", Json.int(rank)),
            ("player", Json.str(Principal.toText(entry.principal))),
            ("totalSpins", Json.int(entry.account.totalSpins)),
            ("totalWagered", Json.int(entry.account.totalWagered)),
          ])]);
          rank += 1;
        };
      };

      // Highest peak balance leaderboard
      let sortedByBalance = Array.sort<PlayerEntry>(players, func(a, b) {
        if (a.account.peakBalance > b.account.peakBalance) { #less }
        else if (a.account.peakBalance < b.account.peakBalance) { #greater }
        else { #equal };
      });
      var highestBalances : [Json.Json] = [];
      rank := 1;
      for (entry in sortedByBalance.vals()) {
        if (rank <= limit and entry.account.peakBalance > 0) {
          highestBalances := Array.append(highestBalances, [Json.obj([
            ("rank", Json.int(rank)),
            ("player", Json.str(Principal.toText(entry.principal))),
            ("peakBalance", Json.int(entry.account.peakBalance)),
            ("currentBalance", Json.int(entry.account.balance)),
          ])]);
          rank += 1;
        };
      };

      // Most wagered leaderboard
      let sortedByWagered = Array.sort<PlayerEntry>(players, func(a, b) {
        if (a.account.totalWagered > b.account.totalWagered) { #less }
        else if (a.account.totalWagered < b.account.totalWagered) { #greater }
        else { #equal };
      });
      var mostWagered : [Json.Json] = [];
      rank := 1;
      for (entry in sortedByWagered.vals()) {
        if (rank <= limit and entry.account.totalWagered > 0) {
          mostWagered := Array.append(mostWagered, [Json.obj([
            ("rank", Json.int(rank)),
            ("player", Json.str(Principal.toText(entry.principal))),
            ("totalWagered", Json.int(entry.account.totalWagered)),
            ("totalWon", Json.int(entry.account.totalWon)),
            ("netProfit", Json.int(entry.account.totalWon - entry.account.totalWagered)),
          ])]);
          rank += 1;
        };
      };

      // All-time records from leaderboard state
      let lb = context.machineStats.leaderboard;
      let allTimeRecords = Json.obj([
        ("biggestSingleWin", Json.obj([
          ("amount", Json.int(lb.biggestWinAmount)),
          ("player", Json.str(switch (lb.biggestWinPlayer) { case (?p) { Principal.toText(p) }; case (null) { "none" } })),
          ("spinId", Json.str(Option.get(lb.biggestWinSpinId, "none"))),
        ])),
        ("mostSpins", Json.obj([
          ("count", Json.int(lb.mostSpinsCount)),
          ("player", Json.str(switch (lb.mostSpinsPlayer) { case (?p) { Principal.toText(p) }; case (null) { "none" } })),
        ])),
        ("highestBalanceEver", Json.obj([
          ("amount", Json.int(lb.highestBalanceEver)),
          ("player", Json.str(switch (lb.highestBalancePlayer) { case (?p) { Principal.toText(p) }; case (null) { "none" } })),
        ])),
        ("jackpotHitCount", Json.int(lb.jackpotHitCount)),
        ("currentJackpotPool", Json.int(context.machineStats.jackpotPool)),
      ]);

      ToolContext.makeSuccess(Json.obj([
        ("biggestWins", Json.arr(biggestWins)),
        ("mostSpins", Json.arr(mostSpins)),
        ("highestBalances", Json.arr(highestBalances)),
        ("mostWagered", Json.arr(mostWagered)),
        ("allTimeRecords", allTimeRecords),
        ("totalPlayers", Json.int(context.machineStats.totalPlayers)),
      ]), cb);
    };
  };
};
