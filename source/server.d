import common;
import std.concurrency;
import std.json;
import core.time;

mixin template Loggerable() {
	import std.experimental.logger;
	private {
		Logger logger = null;
	}
	public {
		void SetLogger(Logger logger) @safe {
			this.logger = logger;
		}
		alias info = defaultLogFunction!(LogLevel.info);
	}
}

void interact(string cmd) {
	import std.process;
	import core.stdc.signal : SIGTERM;
	auto pipes = pipeProcess(cmd, Redirect.stdin|Redirect.stdout);
	scope(exit) {
		kill(pipes.pid, SIGTERM);
	}
	while(true) {
		string s;
		bool running = true;
		receive(
			(string str) { s= str; },
			(Variant v) { running = false; }
		);
		if (!running) { break; }

		pipes.stdin.writeln(s);
		pipes.stdin.flush();
		auto got = pipes.stdout.readln();
		send(ownerTid, got);
	}
}

class RemotePlayer : ReversiPlayer {
private:
	Mark mark;
	NextAction action;
public:
	this(Mark mark) pure nothrow @safe {
		this.mark = mark;
		this.action = NextAction.Pass();
	}
	void SetMark(Mark mark) pure nothrow @safe {
		this.mark = mark;
	}
	Mark GetMark() pure const nothrow @safe {
		return this.mark;
	}
	void SetNextAction(NextAction action) pure nothrow @safe {
		this.action = action;
	}
	NextAction GetNextAction(const ReversiBoard board) pure const {
		return action;
	}
}
class ReversiServer {
	mixin Loggerable;
private:
	string[] clients;
	Tid[] tids;
	int serverstatus;
	int turnPlayerIndex;
	int winplayerIndex;
	ReversiManager game;
	RemotePlayer[] players;

	string MakeStartMsg(int mark){ 
		JSONValue j = [STATUS: START];
		j[YOURMARK] = mark;
		return j.toString();
	}
	string MakeShutdownMsg(){ 
		JSONValue j = [STATUS: SHUTDOWN];
		return j.toString();
	}
	string MakeWaitingMsg() {
		import std.conv : to;
		JSONValue j = [STATUS: PLAYING];
		j[BOARD] = game.GetBoard().IntArray();
		return j.toString();
	}
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
	const int TIMEOUT = 6;
	const int RUNNING = 1;
	const int STOPPING = 0;
	this(string client1, string client2) pure @safe {
		this.clients = [client1, client2];
		this.tids = [];
		this.players = [new RemotePlayer(Mark.BLACK), new RemotePlayer(Mark.WHITE)];
		this.game = new ReversiManager(players[0], players[1]);
		this.turnPlayerIndex = 0;
		this.winplayerIndex = -1;
		this.serverstatus = STOPPING;
	}
	void ServerExit() {
		this.serverstatus = STOPPING;
		this.info("Shutting down...");
		foreach (tid; tids) {
			send(tid, MakeShutdownMsg());
			send(tid, false);
		}
	}
	void ServerStart() {
		import std.algorithm : map;
		import std.array : array;
		// spawn clients
		tids = clients.map!(x => spawn(&interact, x)).array;

		this.info("Handshaking...");
		// handshake
		foreach (i, tid; tids) {
			send(tid, MakeStartMsg(players[i].GetMark()));
			bool timeout = true;
			bool ok = false;
			receiveTimeout(dur!"seconds"(TIMEOUT),
				(string s){
					timeout = false;
					auto j = parseJSON(s);
					if (STATUS in j && j[STATUS].str == OK) {
						ok = true;
					}
				}
			);
			if (timeout) {
				this.info("Timeout");
				ServerExit();
				return;
			}
			if(!ok) {
				this.info("Invalid Response");
				ServerExit();
				return;
			}
			this.info("OK");
		}
		this.serverstatus = RUNNING;
		this.info("Handshake completed");
	}
	
	void Next() {
		if (serverstatus != RUNNING) {
			return;
		}

		auto tid = tids[turnPlayerIndex];

		send(tid, MakeWaitingMsg());
		bool timeout = true;
		bool ok = false;
		NextAction next = NextAction.Pass();
		receiveTimeout(dur!"seconds"(TIMEOUT),
				(string s) {
					timeout = false;
					auto j = parseJSON(s);
					if (ACTION in j && j[ACTION].str == PASS) {
						ok = true;
						next = NextAction.Pass();
					}
					else if (ACTION in j && j[ACTION].str == PUT && PUT in j) {
						ok = true;
						next = NextAction.PutAt(Position(cast(int)j[PUT].array[0].integer, cast(int)j[PUT].array[1].integer));
					}
				});
		if (timeout) {
			this.info("Timeout");
			winplayerIndex = (turnPlayerIndex+1)%2;
			ServerExit();
			return;
		}
		if (!ok) {
			this.info("Invalid Response");
			winplayerIndex = (turnPlayerIndex+1)%2;
			ServerExit();
			return;
		}
		players[turnPlayerIndex].SetNextAction(next);
		try {
			import std.format : format;
			if (next.IsPass()) {
				this.info("turn %d --> Pass".format(game.GetTurn()));
			}
			else {
				auto at = next.GetPutAt();
				this.info("turn %d --> Put(%d, %d)".format(game.GetTurn(), at.x, at.y));
			}
			game.Next();
		}
		catch(Exception e) {
			this.info(e.msg);
			winplayerIndex = (turnPlayerIndex+1)%2;
			ServerExit();
			return;
		}
		if (game.GetBoard().IsGameEnd()) {
			this.info("Game is end");
			auto a =game.GetBoard().Count(players[turnPlayerIndex].GetMark());
			auto b =game.GetBoard().Count(players[(turnPlayerIndex+1)%2].GetMark());

			if (a > b) {
				winplayerIndex = turnPlayerIndex;
			}
			else if (a < b) {
				winplayerIndex = (turnPlayerIndex+1)%2;
			}
			ServerExit();
			return;
		}
		turnPlayerIndex = (turnPlayerIndex+1)%2;
	}

	ReversiManager GetGame() pure @safe {
		return this.game;
	}

	bool IsRunning() {
		return this.serverstatus == RUNNING;
	}
}

import std.stdio;
import std.experimental.logger;
void main(string[] args) {
	auto logger = new FileLogger(stderr);
	auto server = new ReversiServer(args[1], args[2]);
	server.SetLogger(logger);

	server.ServerStart();
	while (server.IsRunning()) {
		write(server.GetGame().GetBoard().String());
		server.Next();
	}
	write(server.GetGame().GetBoard().String());
	writeln("BLACK:" , server.GetGame().GetBoard().Count(Mark.BLACK));
	writeln("WHITE:" , server.GetGame().GetBoard().Count(Mark.WHITE));
}
