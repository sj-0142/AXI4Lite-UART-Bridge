
`timescale 1ns / 1ps

module axi_uart_bridge_tb();

    // Parameters
    parameter CLOCK_FREQ = 100000000;  // 100 MHz
    parameter BAUD_RATE  = 115200;     // 115200 baud
    parameter AXI_ADDR_WIDTH = 32;
    parameter AXI_DATA_WIDTH = 32;

    parameter CLK_PERIOD = 10.0;  // 10ns for 100MHz
    parameter BIT_PERIOD = 1000000000.0 / BAUD_RATE;  // UART bit period in ns

     reg [7:0] received_data;
     
    // Register addresses
    parameter ADDR_TXDATA = 32'h00000000;
    parameter ADDR_RXDATA = 32'h00000004;
    parameter ADDR_STATUS = 32'h00000008;

    // Clock and Reset
    reg                          clk;
    reg                          resetn;

    // AXI4-Lite Master Interface (from testbench perspective)
    reg  [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr;
    reg                          s_axi_awvalid;
    wire                         s_axi_awready;

    reg  [AXI_DATA_WIDTH-1:0]    s_axi_wdata;
    reg                          s_axi_wvalid;
    wire                         s_axi_wready;

    wire [1:0]                   s_axi_bresp;
    wire                         s_axi_bvalid;
    reg                          s_axi_bready;

    reg  [AXI_ADDR_WIDTH-1:0]    s_axi_araddr;
    reg                          s_axi_arvalid;
    wire                         s_axi_arready;

    wire [AXI_DATA_WIDTH-1:0]    s_axi_rdata;
    wire [1:0]                   s_axi_rresp;
    wire                         s_axi_rvalid;
    reg                          s_axi_rready;

    // UART Interface
    wire                         uart_tx;
    reg                          uart_rx;
    
    reg [7:0] received_data;

    reg [7:0] test_data;
    reg [31:0] read_data;
    integer test_count;
    integer error_count;


    axi_uart_bridge #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
    ) dut (
        .clk           (clk),
        .resetn        (resetn),

        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),

        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),

        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),

        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),

        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),

        .uart_tx       (uart_tx),
        .uart_rx       (uart_rx)
    );


    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2) clk = ~clk;
    end
    
    // AXI Write Task
    task axi_write;
        input [31:0] addr;
        input [31:0] data;
        begin
            @(posedge clk);

            // Start write address and data phases simultaneously
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= 1'b1;

            s_axi_wdata   <= data;
            s_axi_wvalid  <= 1'b1;

            s_axi_bready  <= 1'b1;

            // Wait for address ready
            wait (s_axi_awready);
            @(posedge clk);
            s_axi_awvalid <= 1'b0;

            // Wait for data ready
            wait (s_axi_wready);
            @(posedge clk);
            s_axi_wvalid <= 1'b0;

            // Wait for write response
            wait (s_axi_bvalid);
            @(posedge clk);
            s_axi_bready <= 1'b0;

            $display("AXI WRITE: Addr=0x%08h, Data=0x%08h, Resp=%d", addr, data, s_axi_bresp);
        end
    endtask

    // AXI Read Task
    task axi_read;
        input  [31:0] addr;
        output [31:0] data;
        begin
            @(posedge clk);

            // Start read address phase
            s_axi_araddr  <= addr;
            s_axi_arvalid <= 1'b1;
            s_axi_rready  <= 1'b1;

            // Wait for address ready
            wait (s_axi_arready);
            @(posedge clk);
            s_axi_arvalid <= 1'b0;

            // Wait for read data
            wait (s_axi_rvalid);
            data = s_axi_rdata;
            @(posedge clk);
            s_axi_rready <= 1'b0;

            $display("AXI READ: Addr=0x%08h, Data=0x%08h, Resp=%d", addr, data, s_axi_rresp);
        end
    endtask

    // UART Receive Task (simulates external device sending data)
    task uart_send_byte;
        input [7:0] data;
        integer i;
        begin
            $display("UART SEND: Sending byte 0x%02h", data);

            // Start bit
            uart_rx = 1'b0;
            #BIT_PERIOD;

            // Data bits (LSB first)
            for (i = 0; i < 8; i = i + 1) begin
                uart_rx = data[i];
                #BIT_PERIOD;
            end

            // Stop bit
            uart_rx = 1'b1;
            #BIT_PERIOD;
        end
    endtask

    // Monitor UART TX output
    task uart_receive_byte;
        output [7:0] data;
        integer i;
        begin
            // Wait for start bit
            wait (uart_tx == 1'b0);
            $display("UART RX: Start bit detected");

            // Wait for middle of start bit
            #(BIT_PERIOD / 2);

            // Sample data bits
            for (i = 0; i < 8; i = i + 1) begin
                #BIT_PERIOD;
                data[i] = uart_tx;
            end

            // Check stop bit
            #BIT_PERIOD;
            if (uart_tx != 1'b1) begin
                $display("ERROR: Invalid stop bit");
                error_count = error_count + 1;
            end

            $display("UART RX: Received byte 0x%02h", data);
        end
    endtask


    initial begin
        // Initialize signals
        resetn = 1'b0;
        uart_rx = 1'b1;  // UART idle state

        s_axi_awaddr  = 32'h00000000;
        s_axi_awvalid = 1'b0;
        s_axi_wdata   = 32'h00000000;
        s_axi_wvalid  = 1'b0;
        s_axi_bready  = 1'b0;
        s_axi_araddr  = 32'h00000000;
        s_axi_arvalid = 1'b0;
        s_axi_rready  = 1'b0;

        test_count = 0;
        error_count = 0;

        // Wait for some time then release reset
        #(CLK_PERIOD * 10);
        resetn = 1'b1;
        #(CLK_PERIOD * 10);

        $display("========================================");
        $display("Starting AXI4-Lite to UART Bridge Test");
        $display("========================================");


        // Test 1: Read STATUS register (should show tx_busy=0, rx_valid=0)
 

        test_count = test_count + 1;
        $display("TEST %d: Read STATUS register", test_count);

        axi_read(ADDR_STATUS, read_data);
        if (read_data[1:0] == 2'b00) begin
            $display("PASS: STATUS shows tx_busy=0, rx_valid=0");
        end else begin
            $display("FAIL: STATUS = 0x%08h, expected 0x00000000", read_data);
            error_count = error_count + 1;
        end


        // Test 2: UART Transmit via AXI Write to TXDATA
  

        test_count = test_count + 1;
        $display("TEST %d: UART Transmit", test_count);

        test_data = 8'hA5;

        // Start monitoring UART TX in parallel
        fork
            begin
               
                uart_receive_byte(received_data);
                if (received_data == test_data) begin
                    $display("PASS: UART TX transmitted correct data");
                end else begin
                    $display("FAIL: UART TX data mismatch. Expected=0x%02h, Received=0x%02h", 
                            test_data, received_data);
                    error_count = error_count + 1;
                end
            end
            begin
                // Write to TXDATA register
                axi_write(ADDR_TXDATA, {24'h000000, test_data});
            end
        join

        //=====================================================================
        // Test 3: Check tx_busy flag
        //=====================================================================

        test_count = test_count + 1;
        $display("TEST %d: Check tx_busy flag", test_count);

        // Immediately after write, tx_busy should be 1
        axi_read(ADDR_STATUS, read_data);
        if (read_data[0] == 1'b1) begin
            $display("PASS: tx_busy flag is set during transmission");
        end else begin
            $display("FAIL: tx_busy flag not set during transmission");
            error_count = error_count + 1;
        end

        // Wait for transmission to complete
        #(BIT_PERIOD * 12);  // Start + 8 data + stop + margin

        axi_read(ADDR_STATUS, read_data);
        if (read_data[0] == 1'b0) begin
            $display("PASS: tx_busy flag cleared after transmission");
        end else begin
            $display("FAIL: tx_busy flag not cleared after transmission");
            error_count = error_count + 1;
        end

        //=====================================================================
        // Test 4: UART Receive
        //=====================================================================

        test_count = test_count + 1;
        $display("TEST %d: UART Receive", test_count);

        test_data = 8'h5A;

        // Send data via UART RX
        uart_send_byte(test_data);

        // Allow some time for processing
        #(CLK_PERIOD * 10);

        // Check rx_valid flag
        axi_read(ADDR_STATUS, read_data);
        if (read_data[1] == 1'b1) begin
            $display("PASS: rx_valid flag set after reception");
        end else begin
            $display("FAIL: rx_valid flag not set after reception");
            error_count = error_count + 1;
        end

        // Read received data
        axi_read(ADDR_RXDATA, read_data);
        if (read_data[7:0] == test_data) begin
            $display("PASS: Received correct data via UART RX");
        end else begin
            $display("FAIL: UART RX data mismatch. Expected=0x%02h, Received=0x%02h", 
                    test_data, read_data[7:0]);
            error_count = error_count + 1;
        end

        // Check that rx_valid flag is cleared after reading
        #(CLK_PERIOD * 2);
        axi_read(ADDR_STATUS, read_data);
        if (read_data[1] == 1'b0) begin
            $display("PASS: rx_valid flag cleared after reading RXDATA");
        end else begin
            $display("FAIL: rx_valid flag not cleared after reading RXDATA");
            error_count = error_count + 1;
        end

        // Test 5: Loopback Test (multiple bytes)

        test_count = test_count + 1;
        $display("TEST %d: Loopback Test", test_count);

        // Test multiple bytes
        test_loopback(8'h00);
        test_loopback(8'hFF);
        test_loopback(8'hAA);
        test_loopback(8'h55);
        test_loopback(8'h33);

  
        // Test 6: Invalid address read


        test_count = test_count + 1;
        $display("TEST %d: Invalid Address Read", test_count);

        axi_read(32'h0000000C, read_data);  // Invalid address
        // Note: Should return SLVERR response, but we don't check response in this simple test

        // Test Summary
  
        #(CLK_PERIOD * 100);

        $display("========================================");
        $display("Test Summary");
        $display("========================================");
        $display("Total Tests: %d", test_count);
        $display("Errors: %d", error_count);

        if (error_count == 0) begin
            $display("ALL TESTS PASSED!");
        end else begin
            $display("TESTS FAILED!");
        end

        $display("========================================");
        $finish;
    end

    // Loopback test task
    task test_loopback;
        input [7:0] data;
        begin
           

            $display("Loopback test with data: 0x%02h", data);

            // Send via UART RX
            uart_send_byte(data);
            #(CLK_PERIOD * 10);

            // Read received data
            axi_read(ADDR_RXDATA, read_data);

            // Echo back via UART TX
            fork
                uart_receive_byte(received_data);
                axi_write(ADDR_TXDATA, {24'h000000, read_data[7:0]});
            join

            if (received_data == data) begin
                $display("PASS: Loopback successful for 0x%02h", data);
            end else begin
                $display("FAIL: Loopback failed for 0x%02h, got 0x%02h", data, received_data);
                error_count = error_count + 1;
            end
        end
    endtask


    // Simulation Control

    // Timeout
    initial begin
        #(BIT_PERIOD * 1000);  // Long timeout
        $display("ERROR: Simulation timeout");
        $finish;
    end

    // Dump waveforms
    initial begin
        $dumpfile("axi_uart_bridge_tb.vcd");
        $dumpvars(0, axi_uart_bridge_tb);
    end

endmodule
