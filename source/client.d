import common;
import std.json;

class ReversiClient {
private:
	ReversiPlayer player;
	string nextMessage;
	int clientstatus;
public:
	const string STATUS = "Status";
	const string START = "Start";
	const string SHUTDOWN = "Shutdown";
	const string PLAYING = "Playing";
	const string OK = "Ok";
	const string BOARD = "Board";
	const string ACTION = "Action";
	const string PASS = "Pass";
	const string PUT = "Put";
	const string YOURMARK = "YourMark";
	const int RUNNING = 1;
	const int STOPPING = 0;

	this(ReversiPlayer player) nothrow @safe {
		this.player = player;
		this.nextMessage = "";
		this.clientstatus = RUNNING;
	}
	void RecvMessage(string msg) {
		import std.conv : to;
		import std.algorithm : map;
		import std.array : array;
		auto j = parseJSON(msg);
		if (STATUS in j && j[STATUS].str == START && YOURMARK in j) {
			JSONValue j2 = [STATUS: OK];
			this.nextMessage = j2.toString();
			this.player.SetMark(cast(Mark)j[YOURMARK].integer);
			return;
		}
		if (STATUS in j && j[STATUS].str == SHUTDOWN) {
			this.nextMessage = "";
			this.clientstatus = STOPPING;
			return;
		}
		if (STATUS in j && j[STATUS].str == PLAYING && BOARD in j) {
			auto board = new ReversiBoard(j[BOARD].array.map!(x => x.integer.to!int).array);
			auto nextAction = player.GetNextAction(board);
			if (nextAction.IsPass()) {
				JSONValue j2 = [ACTION: PASS];
				this.nextMessage = j2.toString();
			}
			else {
				JSONValue j2 = [ACTION: PUT];
				auto at = nextAction.GetPutAt();
				j2[PUT] = [at.x, at.y];
				this.nextMessage = j2.toString();
			}
		}
	}
	string GetNextMessage() {
		return this.nextMessage;
	}
	bool IsRunning() {
		return this.clientstatus == RUNNING;
	}
}
	import std.stdio;
	import players;
	void main() {
		auto client = new ReversiClient(new ReversiRandomPlayer(Mark.BLACK));
		while (client.IsRunning()) {
			string input = readln();
			client.RecvMessage(input);
			string nextMessage = client.GetNextMessage();
			writeln(nextMessage);
			stdout.flush();
		}
	}
