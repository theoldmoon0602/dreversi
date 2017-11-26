import common;
class ReversiMinicandidatesPlayer : ReversiPlayer {
private:
	Mark mark;
	uint depth;

	int CalcActionWorth(const ReversiBoard board, Mark mark, int depth) pure const {
		// 評価が高いほど負の方向に大きな値を返せ
		if (board.IsGameEnd()) {
			if (board.Count(-mark) > board.Count(mark)) {
				return -1000;
			}
			else {
				return 1000;
			}
		}
		if (depth <= 0) {
			// depth が0のときは -mark への評価を返すことになる。
			return cast(int)(board.ListupPuttables(mark).length) - board.size*board.size;
		}
		auto puttables = board.ListupPuttables(mark);
		if (puttables.length == 0) {
			return -(board.size*board.size);
		}
		int maxworth = -10000;
		Position[] candidates = [];
		foreach (at; puttables) {
			auto newBoard = board.PutAt(at.x, at.y, mark);
			auto worth = -CalcActionWorth(newBoard, -mark, depth-1);
			if (worth > maxworth) {
				maxworth = worth;
			}
		}
		return maxworth;
	}

public:
	this(Mark mark, uint depth) pure nothrow @safe {
		this.mark = mark;
		this.depth = depth;
	}
	void SetMark(Mark) pure nothrow @safe {
		this.mark = mark;
	}
	Mark GetMark() pure nothrow const @safe {
		return this.mark;
	}

	NextAction GetNextAction(const ReversiBoard board) pure const {
		import std.random : choice;
		auto puttables = board.ListupPuttables(mark);
		if (puttables.length == 0) {
			return NextAction.Pass();
		}
		int maxworth = -10000; 
		Position[] candidates = [];
		foreach (at; puttables) {
			auto newBoard = board.PutAt(at.x, at.y, mark);
			auto worth = -CalcActionWorth(newBoard, -mark, depth-1);
			if (worth > maxworth) {
				maxworth = worth;
				candidates = [at];
			}
			else if (worth == maxworth) {
				candidates ~= at;
			}
		}
		if (candidates.length == 0) {
			throw new Exception("WHY JAPANESE PEOPLE!!!!");
		}
		return NextAction.PutAt(choice(candidates));
	}
}

class ReversiRandomPlayer : ReversiPlayer {
private:
	Mark mark;
public:
	this(Mark mark) pure nothrow @safe {
		this.mark = mark;
	}
	void SetMark(Mark mark) pure nothrow @safe {
		this.mark = mark;
	}
	Mark GetMark() pure const nothrow @safe {
		return this.mark;
	}
	NextAction GetNextAction(const ReversiBoard board) pure const {
		import std.random : choice;
		auto puttables = board.ListupPuttables(mark);
		if (puttables.length == 0) {
			return NextAction.Pass();
		}
		return NextAction.PutAt(choice(puttables));
	}

}
