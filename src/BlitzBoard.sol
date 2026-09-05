// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.36;

import {ERC721} from "openzeppelin-contracts/contracts/token/ERC721/ERC721.sol";
import {LibBoard} from "./lib/LibBoard.sol";
import {LibMoves} from "./lib/LibMoves.sol";

/// @title Blitz Board — Monad 上的 5×5 闪电棋
/// @notice 每步一笔交易；吃掉对方王即胜，胜者按 gameId 铸一枚奖杯 NFT。
///         多桌并行：不同 gameId 独立 storage，互不冲突。
///         v1 无将军检测（可送王）；超时 180s = 当前行棋方判负。
contract BlitzBoard is ERC721 {
    // ---------- 状态（slot 顺序冻结：games 必须是 slot 0，测试依赖此布局） ----------
    mapping(uint256 => Game) public games; // slot 0
    uint256 public gameCount;              // slot 1

    struct Game {
        uint256 board;        // slot 0
        address white;        // slot 1
        address black;        // slot 2
        uint64 lastMoveAt;    // slot 3（以下四个打包同 slot）
        uint32 moveCount;
        Status status;
        uint8 toMove;         // 0 白 / 1 黑
    }

    enum Status {
        Waiting,  // 0 已创建未加入
        Active,   // 1 对局中
        Finished  // 2 已结束
    }

    uint64 constant TIMEOUT = 180;

    event Created(uint256 indexed gameId, address indexed white);
    event Joined(uint256 indexed gameId, address indexed black);
    event MovePlayed(uint256 indexed gameId, uint8 from, uint8 to, uint8 piece);
    event Ended(uint256 indexed gameId, address indexed winner, uint8 reason); // 0 吃王 1 超时 2 认输

    constructor() ERC721("Blitz Board Trophy", "BBT") {}

    // ---------- 创建 / 加入 ----------

    function create() external returns (uint256 id) {
        id = ++gameCount;
        Game storage g = games[id];
        g.board = LibBoard.OPENING;
        g.white = msg.sender;
        g.toMove = 0;
        emit Created(id, msg.sender);
    }

    /// @notice 自定义开局（用于变体与测试）：校验棋子全在 5×5 内且双王各一
    function createCustom(uint256 board) external returns (uint256 id) {
        uint8 wK;
        uint8 bK;
        for (uint8 sq = 0; sq < 64; ++sq) {
            uint8 p = LibBoard.get(board, sq);
            if (p == LibBoard.EMPTY) continue;
            require(LibBoard.inPlay(sq), "piece out of 5x5");
            if (p == LibBoard.W_KING) ++wK;
            if (p == LibBoard.B_KING) ++bK;
        }
        require(wK == 1 && bK == 1, "need both kings");

        id = ++gameCount;
        Game storage g = games[id];
        g.board = board;
        g.white = msg.sender;
        g.toMove = 0;
        emit Created(id, msg.sender);
    }

    function join(uint256 id) external {
        Game storage g = games[id];
        require(g.white != address(0), "no game");
        require(g.status == Status.Waiting, "not waiting");
        require(msg.sender != g.white, "self join"); // A1
        g.black = msg.sender;
        g.status = Status.Active;
        g.lastMoveAt = uint64(block.timestamp);      // A22：超时从加入起算
        emit Joined(id, msg.sender);
    }

    // ---------- 走子 ----------

    function move(uint256 id, uint8 from, uint8 to) external {
        Game storage g = games[id];
        require(g.status == Status.Active, "not active"); // A3/A21
        bool whiteToMove = g.toMove == 0;
        require(msg.sender == (whiteToMove ? g.white : g.black), "not your turn"); // A2

        require(LibMoves.isLegal(g.board, from, to, whiteToMove), "illegal");

        uint8 piece = LibBoard.get(g.board, from);
        uint8 target = LibBoard.get(g.board, to);

        // 升变：兵到底线只升后（v1 简化）
        uint8 placed = piece;
        if (piece == LibBoard.W_PAWN && LibBoard.rankOf(to) == 4) placed = LibBoard.W_QUEEN;
        if (piece == LibBoard.B_PAWN && LibBoard.rankOf(to) == 0) placed = LibBoard.B_QUEEN;

        g.board = LibBoard.set(LibBoard.set(g.board, from, LibBoard.EMPTY), to, placed);
        g.toMove = whiteToMove ? 1 : 0;
        g.moveCount += 1;
        g.lastMoveAt = uint64(block.timestamp);

        emit MovePlayed(id, from, to, piece);

        // v1 胜负：吃掉对方的王（无将军检测，见方案 §3.1）
        if (target == LibBoard.W_KING || target == LibBoard.B_KING) {
            g.status = Status.Finished; // CEI：先改状态再 mint（A3/A8）
            _mint(msg.sender, id);      // tokenId = gameId
            emit Ended(id, msg.sender, 0);
        }
    }

    // ---------- 终局 ----------

    /// @notice 当前行棋方超时判负；由胜者（对手）调用
    function claimTimeout(uint256 id) external {
        Game storage g = games[id];
        require(g.status == Status.Active, "not active");
        require(block.timestamp >= g.lastMoveAt + TIMEOUT, "not timed out"); // A7
        address loser = g.toMove == 0 ? g.white : g.black;
        address winner = loser == g.white ? g.black : g.white;
        require(msg.sender == winner, "only winner");
        g.status = Status.Finished;
        _mint(winner, id);
        emit Ended(id, winner, 1);
    }

    /// @notice 认输：调用者为自己认输，对方获胜
    function resign(uint256 id) external {
        Game storage g = games[id];
        require(g.status == Status.Active, "not active");
        require(msg.sender == g.white || msg.sender == g.black, "not a player");
        address winner = msg.sender == g.white ? g.black : g.white;
        g.status = Status.Finished;
        _mint(winner, id);
        emit Ended(id, winner, 2);
    }
}
