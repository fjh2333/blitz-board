// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {BlitzBoard} from "../src/BlitzBoard.sol";
import {LibBoard} from "../src/lib/LibBoard.sol";
import {LibMoves} from "../src/lib/LibMoves.sol";

contract BlitzBoardTest is Test {
    BlitzBoard internal blitz;
    address internal black = makeAddr("black");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        blitz = new BlitzBoard();
    }

    function _newGame() internal returns (uint256 id) {
        id = blitz.create();
        vm.prank(black);
        blitz.join(id);
    }

    // ---------- 编解码 ----------

    function test_Opening_Decode() public pure {
        // a1 车(4) b1 马(2) c1 象(3) d1 后(5) e1 王(6)
        assertEq(LibBoard.get(LibBoard.OPENING, 0), LibBoard.W_ROOK);
        assertEq(LibBoard.get(LibBoard.OPENING, 1), LibBoard.W_KNIGHT);
        assertEq(LibBoard.get(LibBoard.OPENING, 4), LibBoard.W_KING);
        assertEq(LibBoard.get(LibBoard.OPENING, 8), LibBoard.W_PAWN);
        assertEq(LibBoard.get(LibBoard.OPENING, 12), LibBoard.W_PAWN);
        assertEq(LibBoard.get(LibBoard.OPENING, 16), LibBoard.EMPTY);
        assertEq(LibBoard.get(LibBoard.OPENING, 24), LibBoard.B_PAWN);
        assertEq(LibBoard.get(LibBoard.OPENING, 32), LibBoard.B_ROOK);
        assertEq(LibBoard.get(LibBoard.OPENING, 33), LibBoard.B_KNIGHT);
        assertEq(LibBoard.get(LibBoard.OPENING, 36), LibBoard.B_KING);
        // 盘外格恒空
        assertEq(LibBoard.get(LibBoard.OPENING, 5), 0); // f1
        assertEq(LibBoard.get(LibBoard.OPENING, 63), 0); // h8
    }

    function test_SetGet_Roundtrip() public pure {
        uint256 b = LibBoard.OPENING;
        b = LibBoard.set(b, 20, LibBoard.W_PAWN);
        assertEq(LibBoard.get(b, 20), LibBoard.W_PAWN);
        b = LibBoard.set(b, 20, LibBoard.EMPTY);
        assertEq(b, LibBoard.OPENING);
    }

    // ---------- 创建 / 加入 ----------

    function test_Create() public {
        uint256 id = blitz.create();
        (uint256 board, address white,, , , BlitzBoard.Status status,) = blitz.games(id);
        assertEq(board, LibBoard.OPENING);
        assertEq(white, address(this));
        assertEq(uint8(status), uint8(BlitzBoard.Status.Waiting));
        assertEq(blitz.gameCount(), 1);
    }

    function test_Join() public {
        uint256 id = blitz.create();
        vm.prank(black);
        blitz.join(id);
        (, address w, address b, uint64 lastMoveAt, , BlitzBoard.Status status,) = blitz.games(id);
        assertEq(b, black);
        assertEq(uint8(status), uint8(BlitzBoard.Status.Active));
        assertGt(lastMoveAt, 0);
    }

    function test_Join_Self_Revert() public {
        uint256 id = blitz.create();
        vm.expectRevert("self join");
        blitz.join(id);
    }

    function test_Join_Twice_Revert() public {
        uint256 id = blitz.create();
        vm.prank(black);
        blitz.join(id);
        vm.prank(stranger);
        vm.expectRevert("not waiting");
        blitz.join(id);
    }

    // ---------- 走子 ----------

    function test_Move_Pawn() public {
        uint256 id = blitz.create();
        vm.prank(black);
        blitz.join(id);
        // 白兵 e2→e3：sq12 → sq20
        blitz.move(id, 12, 20);
        (uint256 board,,,, uint32 moveCount, , uint8 toMove) = blitz.games(id);
        assertEq(LibBoard.get(board, 12), 0);
        assertEq(LibBoard.get(LibBoard.OPENING, 12), LibBoard.W_PAWN);
        assertEq(LibBoard.get(board, 20), LibBoard.W_PAWN);
        assertEq(moveCount, 1);
        assertEq(toMove, 1); // 轮黑
    }

    function test_Move_WrongTurn_Revert() public {
        uint256 id = blitz.create();
        vm.prank(black);
        blitz.join(id);
        // 白先走，黑不能动
        vm.prank(black);
        vm.expectRevert("not your turn");
        blitz.move(id, 28, 20);
    }

    function test_Move_NotPlayer_Revert() public {
        uint256 id = blitz.create();
        vm.prank(black);
        blitz.join(id);
        vm.prank(stranger);
        vm.expectRevert("not your turn");
        blitz.move(id, 12, 20);
    }

    function test_Move_OutOfPlay_Revert() public {
        uint256 id = blitz.create();
        vm.prank(black);
        blitz.join(id);
        // 车 a1 → f1（sq5 盘外）
        vm.expectRevert("illegal");
        blitz.move(id, 0, 5);
    }

    function test_Move_Knight() public {
        uint256 id = blitz.create();
        vm.prank(black);
        blitz.join(id);
        // 马 b1→c3：sq1 → sq18
        blitz.move(id, 1, 18);
        (uint256 board,,,,,,) = blitz.games(id);
        assertEq(LibBoard.get(board, 18), LibBoard.W_KNIGHT);
        assertEq(LibBoard.get(board, 1), 0);
    }

    function test_Move_Rook_Blocked() public {
        uint256 id = blitz.create();
        vm.prank(black);
        blitz.join(id);
        // 白车 a1 不能越过 a2 白兵到 a3
        vm.expectRevert("illegal");
        blitz.move(id, 0, 16);
    }

    function test_Move_BeforeJoin_Revert() public {
        uint256 id = blitz.create();
        vm.expectRevert("not active");
        blitz.move(id, 12, 20);
    }

    // ---------- 吃王即胜 + mint ----------

    function test_CaptureKing_Wins_And_Mints() public {
        uint256 b;
        b = LibBoard.set(0, 0, LibBoard.W_ROOK);   // 白车 a1
        b = LibBoard.set(b, 4, LibBoard.W_KING);   // 白王 e1
        b = LibBoard.set(b, 32, LibBoard.B_KING);  // 黑王 a5
        uint256 id = blitz.createCustom(b);
        vm.prank(stranger);
        blitz.join(id);

        blitz.move(id, 0, 32); // 车吃王

        (,,, , , BlitzBoard.Status status,) = blitz.games(id);
        assertEq(uint8(status), uint8(BlitzBoard.Status.Finished));
        assertEq(blitz.ownerOf(id), address(this)); // tokenId = gameId
        assertEq(blitz.balanceOf(address(this)), 1);
    }

    function test_Move_AfterEnd_Revert() public {
        uint256 b = LibBoard.set(0, 0, LibBoard.W_ROOK);
        b = LibBoard.set(b, 4, LibBoard.W_KING);
        b = LibBoard.set(b, 32, LibBoard.B_KING);
        uint256 id = blitz.createCustom(b);
        vm.prank(stranger);
        blitz.join(id);
        blitz.move(id, 0, 32); // 吃王终局
        vm.expectRevert("not active");
        blitz.move(id, 4, 12);
    }

    // ---------- 认输 / 超时 ----------

    function test_Resign() public {
        uint256 id = blitz.create();
        vm.prank(stranger);
        blitz.join(id);
        vm.prank(stranger); // 黑方认输
        blitz.resign(id);
        assertEq(blitz.ownerOf(id), address(this));
        (, , , , , BlitzBoard.Status status,) = blitz.games(id);
        assertEq(uint8(status), uint8(BlitzBoard.Status.Finished));
    }

    function test_Timeout() public {
        uint256 id = blitz.create();
        vm.prank(stranger);
        blitz.join(id);
        blitz.move(id, 12, 20); // 白走，轮黑
        // 黑超时 → 白胜
        vm.warp(block.timestamp + 181);
        blitz.claimTimeout(id);
        assertEq(blitz.ownerOf(id), address(this));
    }

    function test_Timeout_TooEarly_Revert() public {
        uint256 id = blitz.create();
        vm.prank(stranger);
        blitz.join(id);
        blitz.move(id, 12, 20);
        vm.warp(block.timestamp + 100);
        vm.expectRevert("not timed out");
        blitz.claimTimeout(id);
    }

    function test_Timeout_Waiting_Revert() public {
        uint256 id = blitz.create();
        vm.warp(block.timestamp + 1000);
        vm.expectRevert("not active");
        blitz.claimTimeout(id);
    }

    // ---------- 升变 ----------

    function test_Promotion() public {
        // 白兵 d4，黑象 e5；白 d4xe5 升后
        uint256 b = LibBoard.set(0, 3, LibBoard.W_KING);  // 白王 d1
        b = LibBoard.set(b, 27, LibBoard.W_PAWN);         // 白兵 d4
        b = LibBoard.set(b, 36, LibBoard.B_KING);         // 黑王 e5
        b = LibBoard.set(b, 35, LibBoard.B_QUEEN);        // 黑后 d5
        uint256 id = blitz.createCustom(b);
        vm.prank(stranger);
        blitz.join(id);

        blitz.move(id, 27, 36); // 兵斜吃升后
        (uint256 board,,,,,,) = blitz.games(id);
        assertEq(LibBoard.get(board, 36), LibBoard.W_QUEEN);
        assertEq(LibBoard.get(board, 27), 0);
    }

    // ---------- 走法合法性（LibMoves 直测） ----------

    function test_Knight_Jumps() public pure {
        assertTrue(LibMoves.isLegal(LibBoard.OPENING, 1, 18, true)); // b1→c3
        assertFalse(LibMoves.isLegal(LibBoard.OPENING, 1, 19, true)); // b1→d3 非日字
    }

    function test_Pawn_Rules() public pure {
        // 从空盘构造：白兵 d3(19)，黑兵 e4(28)
        uint256 b = LibBoard.set(0, 19, LibBoard.W_PAWN);
        b = LibBoard.set(b, 28, LibBoard.B_PAWN);
        assertTrue(LibMoves.isLegal(b, 19, 28, true));   // 白斜吃有敌
        uint256 b2 = LibBoard.set(b, 28, LibBoard.EMPTY);
        assertFalse(LibMoves.isLegal(b2, 19, 28, true)); // 白斜进但目标空 → 非法
        assertTrue(LibMoves.isLegal(b2, 19, 27, true));  // 白直进 d4 空 → 合法
        uint256 b3 = LibBoard.set(b2, 27, LibBoard.W_PAWN);
        assertFalse(LibMoves.isLegal(b3, 19, 27, true)); // 白直进被己方挡 → 非法
        assertTrue(LibMoves.isLegal(b, 28, 19, false));  // 黑斜吃白兵
        assertTrue(LibMoves.isLegal(b, 28, 20, false));  // 黑直进 e3 空
        assertFalse(LibMoves.isLegal(b, 28, 36, false)); // 黑两步 → v1 禁止
    }

    function test_Ray_Wall_OutOfPlay() public pure {
        // 象 a1→…：斜线在 5×5 内不会穿盘外；但目标盘外必须非法
        assertFalse(LibMoves.isLegal(LibBoard.OPENING, 0, 9, true)); // a1→b2 有兵，非法
    }

    function test_AntiDiagonal_Slider() public pure {
        // 回归：反斜线（df 与 dr 异号）此前被误判为非法
        // 白后 d4(27)，黑兵 e3(20)：d4xe3 反斜线吃
        uint256 b = LibBoard.set(0, 27, LibBoard.W_QUEEN);
        b = LibBoard.set(b, 20, LibBoard.B_PAWN);
        assertTrue(LibMoves.isLegal(b, 27, 20, true));
        // 白象 e4(28) → d3(19)：反斜线
        uint256 b2 = LibBoard.set(0, 28, LibBoard.W_BISHOP);
        assertTrue(LibMoves.isLegal(b2, 28, 19, true));
        // 反斜线穿过的中间格必须为空：后 d4(27) → b2(9)，中间 c3(18) 有子则非法
        uint256 b3 = LibBoard.set(0, 27, LibBoard.W_QUEEN);
        b3 = LibBoard.set(b3, 9, LibBoard.B_PAWN);
        b3 = LibBoard.set(b3, 18, LibBoard.B_PAWN); // 挡路
        assertFalse(LibMoves.isLegal(b3, 27, 9, true));
    }
}
