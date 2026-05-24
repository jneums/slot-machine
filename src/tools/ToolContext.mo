import Principal "mo:base/Principal";
import Result "mo:base/Result";
import McpTypes "mo:mcp-motoko-sdk/mcp/Types";
import Json "mo:json";
import Map "mo:map/Map";

module ToolContext {

  // ── Symbol type ──
  public type Symbol = {
    #cherry;
    #lemon;
    #bell;
    #star;
    #diamond;
    #seven;
  };

  // ── Player account ──
  public type PlayerAccount = {
    var balance : Nat;
    var totalSpins : Nat;
    var totalWagered : Nat;
    var totalWon : Nat;
    var biggestWin : Nat;
    var peakBalance : Nat; // highest balance ever achieved
    var lastFaucetClaim : Nat; // timestamp nanos
    createdAt : Nat;
  };

  // ── Spin result (immutable record) ──
  public type SpinResult = {
    id : Text;
    player : Principal;
    bet : Nat;
    reels : [Symbol];
    payout : Nat;
    multiplier : Nat;
    jackpotWon : Nat; // progressive jackpot payout (0 if not jackpot)
    seed : Blob;
    timestamp : Nat;
  };

  // ── Leaderboard record ──
  public type LeaderboardRecord = {
    var biggestWinAmount : Nat;
    var biggestWinPlayer : ?Principal;
    var biggestWinSpinId : ?Text;
    var mostSpinsPlayer : ?Principal;
    var mostSpinsCount : Nat;
    var highestBalanceEver : Nat;
    var highestBalancePlayer : ?Principal;
    var jackpotHitCount : Nat;
    var totalFreeSpinsAwarded : Nat;
  };

  // ── Symbol frequency tracker ──
  public type SymbolFrequency = {
    var cherry : Nat;
    var lemon : Nat;
    var bell : Nat;
    var star : Nat;
    var diamond : Nat;
    var seven : Nat;
  };

  // ── Machine stats ──
  public type MachineStats = {
    var totalSpins : Nat;
    var totalWagered : Nat;
    var totalPaidOut : Nat;
    var totalPlayers : Nat;
    var jackpotPool : Nat; // progressive jackpot pool
    leaderboard : LeaderboardRecord;
    symbolFrequency : SymbolFrequency;
  };

  // ── Context shared between tools and the main canister ──
  public type ToolContext = {
    canisterPrincipal : Principal;
    owner : Principal;
    appContext : McpTypes.AppContext;
    accounts : Map.Map<Principal, PlayerAccount>;
    spins : Map.Map<Text, SpinResult>;
    playerSpins : Map.Map<Principal, [Text]>;
    spinCounter : { var count : Nat };
    machineStats : MachineStats;
    getRandom : () -> async Blob;
  };

  // ── Constants ──
  public let MIN_BET : Nat = 1;
  public let MAX_BET : Nat = 100;
  public let FAUCET_AMOUNT : Nat = 100;
  public let FAUCET_COOLDOWN_NANOS : Nat = 14_400_000_000_000; // 4 hours
  public let JACKPOT_RAKE_PERCENT : Nat = 2; // 2% of each bet goes to jackpot pool

  // ── Symbol helpers ──
  public func symbolToText(s : Symbol) : Text {
    switch (s) {
      case (#cherry) { "🍒" };
      case (#lemon) { "🍋" };
      case (#bell) { "🔔" };
      case (#star) { "⭐" };
      case (#diamond) { "💎" };
      case (#seven) { "🎰" };
    };
  };

  public func symbolToName(s : Symbol) : Text {
    switch (s) {
      case (#cherry) { "cherry" };
      case (#lemon) { "lemon" };
      case (#bell) { "bell" };
      case (#star) { "star" };
      case (#diamond) { "diamond" };
      case (#seven) { "seven" };
    };
  };

  // Map a value 0-99 to a symbol using weighted distribution
  public func valueToSymbol(value : Nat) : Symbol {
    if (value < 25) { #cherry }
    else if (value < 50) { #lemon }
    else if (value < 70) { #bell }
    else if (value < 85) { #star }
    else if (value < 95) { #diamond }
    else { #seven };
  };

  // Determine payout multiplier from 3 reels (v0.2.0 rebalanced)
  public func getMultiplier(reels : [Symbol]) : Nat {
    assert reels.size() == 3;
    let r0 = reels[0];
    let r1 = reels[1];
    let r2 = reels[2];

    // Three of a kind
    if (symbolsEqual(r0, r1) and symbolsEqual(r1, r2)) {
      switch (r0) {
        case (#seven) { 150 };   // was 100
        case (#diamond) { 50 };  // unchanged
        case (#star) { 25 };     // unchanged
        case (#bell) { 12 };     // was 10
        case (#lemon) { 7 };     // was 5
        case (#cherry) { 5 };    // was 3
      };
    }
    // Any pair
    else if (symbolsEqual(r0, r1) or symbolsEqual(r1, r2) or symbolsEqual(r0, r2)) {
      1; // push — get bet back
    }
    // No match
    else {
      0;
    };
  };

  // Get the pair symbol when exactly 2 match (for near-miss messages)
  public func getPairSymbol(reels : [Symbol]) : ?Symbol {
    let r0 = reels[0];
    let r1 = reels[1];
    let r2 = reels[2];

    // Don't return for triples
    if (symbolsEqual(r0, r1) and symbolsEqual(r1, r2)) {
      return null;
    };
    if (symbolsEqual(r0, r1)) { return ?r0 };
    if (symbolsEqual(r1, r2)) { return ?r1 };
    if (symbolsEqual(r0, r2)) { return ?r0 };
    null;
  };

  public func symbolsEqual(a : Symbol, b : Symbol) : Bool {
    switch (a, b) {
      case (#cherry, #cherry) { true };
      case (#lemon, #lemon) { true };
      case (#bell, #bell) { true };
      case (#star, #star) { true };
      case (#diamond, #diamond) { true };
      case (#seven, #seven) { true };
      case _ { false };
    };
  };

  // Track symbol frequency
  public func trackSymbol(freq : SymbolFrequency, s : Symbol) {
    switch (s) {
      case (#cherry) { freq.cherry += 1 };
      case (#lemon) { freq.lemon += 1 };
      case (#bell) { freq.bell += 1 };
      case (#star) { freq.star += 1 };
      case (#diamond) { freq.diamond += 1 };
      case (#seven) { freq.seven += 1 };
    };
  };

  // ── Response helpers ──
  public func makeError(message : Text, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    cb(#ok({ content = [#text({ text = "Error: " # message })]; isError = true; structuredContent = null }));
  };

  public func makeSuccess(structured : Json.Json, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    cb(#ok({ content = [#text({ text = Json.stringify(structured, null) })]; isError = false; structuredContent = ?structured }));
  };

  public func makeTextSuccess(text : Text, cb : (Result.Result<McpTypes.CallToolResult, McpTypes.HandlerError>) -> ()) {
    cb(#ok({ content = [#text({ text = text })]; isError = false; structuredContent = null }));
  };
};
