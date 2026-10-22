import mygoose from "../..";
import mygoose_charts from "../../extras/charts";
import mygoose_performance from ".";
import os;
fn main() {
    var state = mygoose_performance::Performance {}; let arguments = args(); var benchmark: i64 = 4000000000; var warmup: i64 = 1000000000;
    var synced = true;
    for argument in arguments {
        if argument == "--timer" { synced = false; }
        if argument == "--steady" { warmup = 32000000000; benchmark = 8000000000; }
    }
    if arguments.len > 1 {
        if arguments[1] == "--bench-30" { state.rate = 0; }
        if arguments[1] == "--bench-60" { state.rate = 1; }
        if arguments[1] == "--bench-120" { state.rate = 2; }
    }
    mygoose_performance::run(state, benchmark, synced, warmup);
}
