

//////////////////////////////
// Transaction Class
//////////////////////////////
class transaction;
  bit newd;
  rand bit [11:0] din;
  bit [11:0] dout;

  function transaction copy();
    copy = new();
    copy.newd = this.newd;
    copy.din  = this.din;
    copy.dout = this.dout;
  endfunction
endclass


//////////////////////////////
// Generator Class (manual coverage + adaptive)
//////////////////////////////
class generator;
  transaction tr;
  mailbox #(transaction) mbx;
  event done;
  int count = 0;
  event sconext;    // sync event with scoreboard

  bit seen_low;
  bit seen_mid;
  bit seen_high;

  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
    tr = new();
    seen_low = 0; seen_mid = 0; seen_high = 0;
  endfunction

  function real coverage_percent();
    return ((seen_low + seen_mid + seen_high) * 100.0 / 3.0);
  endfunction

  task run();
    repeat(count) begin
      assert(tr.randomize()) else $error("[GEN] : Randomization Failed");
      // update manual coverage
      if (tr.din < 16) seen_low = 1;
      else if (tr.din < 2048) seen_mid = 1;
      else seen_high = 1;

      mbx.put(tr.copy());
      $display("[GEN] : din=%0d, coverage=%0.2f%% (low=%0b mid=%0b high=%0b)",
               tr.din, coverage_percent(), seen_low, seen_mid, seen_high);

      // adaptive behavior: bias to edge case if all bins not seen
      if ((seen_low + seen_mid + seen_high) < 3) begin
        tr.din = 12'hFFF; // force edge case occasionally
        $display("[GEN] : Forcing edge-case din=%0d", tr.din);
      end

      @(sconext);
    end
    -> done;
  endtask
endclass


//////////////////////////////
// Driver Class
//////////////////////////////
class driver;
  virtual spi_if vif;
  transaction tr;
  mailbox #(transaction) mbx;
  mailbox #(bit [11:0]) mbxds;

  function new(mailbox #(bit [11:0]) mbxds, mailbox #(transaction) mbx);
    this.mbx = mbx;
    this.mbxds = mbxds;
  endfunction

  task reset();
    vif.rst <= 1'b1;
    vif.newd <= 1'b0;
    vif.din <= 12'h0;
    repeat(10) @(posedge vif.clk);
    vif.rst <= 1'b0;
    repeat(5) @(posedge vif.clk);
    $display("[DRV] : RESET DONE");
    $display("-----------------------------------------");
  endtask

  task run();
    forever begin
      mbx.get(tr);
      vif.newd <= 1'b1;
      vif.din <= tr.din;
      mbxds.put(tr.din);
      @(posedge vif.sclk);
      vif.newd <= 1'b0;
      @(posedge vif.done);
      $display("[DRV] : DATA SENT : %0d", tr.din);
      @(posedge vif.sclk);
    end
  endtask
endclass


//////////////////////////////
// Monitor Class
//////////////////////////////
class monitor;
  transaction tr;
  mailbox #(bit [11:0]) mbx;
  virtual spi_if vif;

  function new(mailbox #(bit [11:0]) mbx);
    this.mbx = mbx;
  endfunction

  task run();
    tr = new();
    forever begin
      @(posedge vif.sclk);
      @(posedge vif.done);
      tr.dout = vif.dout;
      @(posedge vif.sclk);
      $display("[MON] : DATA RECEIVED : %0d", tr.dout);
      mbx.put(tr.dout);
    end
  endtask
endclass


//////////////////////////////
// Scoreboard Class (simple classification)
//////////////////////////////
class scoreboard;
  mailbox #(bit [11:0]) mbxds, mbxms;
  bit [11:0] ds, ms;
  event sconext;

  function new(mailbox #(bit [11:0]) mbxds, mailbox #(bit [11:0]) mbxms);
    this.mbxds = mbxds;
    this.mbxms = mbxms;
  endfunction

  task run();
    forever begin
      mbxds.get(ds);
      mbxms.get(ms);
      $display("[SCO] : DRV=%0d, MON=%0d", ds, ms);
      if (ds === ms) begin
        $display("[SCO] : DATA MATCHED");
      end else begin
        if (ds === 'x || ms === 'x)
          $display("[SCO] : ERROR CLASS: Unknown/Uninitialized data");
        else if (ds > ms)
          $display("[SCO] : ERROR CLASS: Data Loss/Truncation suspected");
        else
          $display("[SCO] : ERROR CLASS: Timing/Data Mismatch");
      end
      $display("-----------------------------------------");
      ->sconext;
    end
  endtask
endclass


//////////////////////////////
// Environment Class
//////////////////////////////
class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;

  mailbox #(transaction) mbxgd;
  mailbox #(bit [11:0]) mbxds;
  mailbox #(bit [11:0]) mbxms;

  event nextgs; // used as sconext
  virtual spi_if vif;

  function new(virtual spi_if vif);
    mbxgd = new();
    mbxms = new();
    mbxds = new();
    gen = new(mbxgd);
    drv = new(mbxds, mbxgd);
    mon = new(mbxms);
    sco = new(mbxds, mbxms);

    this.vif = vif;
    drv.vif = this.vif;
    mon.vif = this.vif;

    gen.sconext = nextgs;
    sco.sconext = nextgs;
  endfunction

  task pre_test();
    drv.reset();
  endtask

  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask

  task post_test();
    wait(gen.done.triggered);
    $finish();
  endtask

  task run();
    pre_test();
    test();
    post_test();
  endtask
endclass


//////////////////////////////
// Testbench Top
//////////////////////////////
module tb;
  spi_if vif();               // interface should be declared in your design files

  top dut(vif.clk, vif.rst, vif.newd, vif.din, vif.dout, vif.done);

  initial vif.clk = 0;
  always #10 vif.clk = ~vif.clk;

  environment env;

  // If your top instantiates master with name m1, this connects sclk
  assign vif.sclk = dut.m1.sclk;

  initial begin
    env = new(vif);
    env.gen.count = 10;   // set number of transactions
    env.run();
  end

  initial begin
    $dumpfile("dump.vcd");
    $dumpvars(0, tb);
  end
endmodule  
