import mygoose from "../src";
import mygoose_charts from "../extras/charts";
import mygoose_performance from "../apps/performance";
fn main() { var state = mygoose_performance::Performance {}; mygoose_performance::run(state); }
