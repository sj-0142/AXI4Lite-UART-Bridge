module axi_uart_bridge #(
    parameter CLOCK_FREQ = 100000000,  // System clock frequency in Hz
    parameter BAUD_RATE  = 115200,     // UART baud rate
    parameter AXI_ADDR_WIDTH = 32,     // AXI address width
    parameter AXI_DATA_WIDTH = 32      // AXI data width
)(
    // Clock and Reset
    input  wire                          clk,
    input  wire                          resetn,

    // AXI4-Lite Slave Interface
    // Write Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output reg                           s_axi_awready,

    // Write Data Channel
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire                          s_axi_wvalid,
    output reg                           s_axi_wready,

    // Write Response Channel
    output reg  [1:0]                    s_axi_bresp,
    output reg                           s_axi_bvalid,
    input  wire                          s_axi_bready,

    // Read Address Channel
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output reg                           s_axi_arready,

    // Read Data Channel
    output reg  [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]                    s_axi_rresp,
    output reg                           s_axi_rvalid,
    input  wire                          s_axi_rready,

    // UART Interface
    output wire                          uart_tx,
    input  wire                          uart_rx
);

    // Register addresses (word-aligned)
    localparam ADDR_TXDATA = 4'h0;  // 0x00
    localparam ADDR_RXDATA = 4'h1;  // 0x04
    localparam ADDR_STATUS = 4'h2;  // 0x08

    // AXI Response codes
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;
    localparam INVADD = 2'b11;

    // Internal signals
    wire [3:0] write_addr_reg;
    wire [3:0] read_addr_reg;

    // UART interface signals
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;
    wire [7:0] rx_data;
    wire       rx_valid;
    reg        rx_read;

    // AXI Write transaction tracking
    reg        write_addr_valid;
    reg        write_data_valid;
    reg [3:0]  write_addr_latched;
    reg [31:0] write_data_latched;

    // AXI Read transaction tracking
    reg        read_transaction_active;
    reg [3:0]  read_addr_latched;

    // Extract word-aligned address (ignore lower 2 bits - address is byte based)
    assign write_addr_reg = s_axi_awaddr[5:2];
    assign read_addr_reg  = s_axi_araddr[5:2];
    
    // Register Map:
    // 0x00: TXDATA (write-only) - Writing triggers UART transmit
    // 0x04: RXDATA (read-only)  - Reading gives last received byte, clears rx_valid
    // 0x08: STATUS (read-only)  - bit[0] = tx_busy, bit[1] = rx_valid

   
    // UART Module Instantiations
    uart_tx #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_tx (
        .clk      (clk),
        .resetn   (resetn),
        .tx_start (tx_start),
        .tx_data  (tx_data),
        .tx_busy  (tx_busy),
        .uart_tx  (uart_tx)
    );

    uart_rx #(
        .CLOCK_FREQ(CLOCK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_uart_rx (
        .clk      (clk),
        .resetn   (resetn),
        .uart_rx  (uart_rx),
        .rx_data  (rx_data),
        .rx_valid (rx_valid),
        .rx_read  (rx_read)
    );


    // AXI4-Lite Write Transaction Handling


    // Write Address Channel (1/5)
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_awready      <= 1'b0;
            write_addr_valid   <= 1'b0;
            write_addr_latched <= 4'h0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                // Address handshake completed
                s_axi_awready      <= 1'b0;
                write_addr_valid   <= 1'b1;
                write_addr_latched <= write_addr_reg;
            end else if (!s_axi_awready && s_axi_awvalid) begin
                // Address valid, assert ready
                s_axi_awready <= 1'b1;
            end else if (write_addr_valid && write_data_valid) begin
                // Both address and data received, ready for next transaction
                write_addr_valid <= 1'b0;
                s_axi_awready    <= 1'b0;
            end
        end
    end

    // Write Data Channel (2/5)
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_wready       <= 1'b0;
            write_data_valid   <= 1'b0;
            write_data_latched <= 32'h00000000;
        end else begin
            if (s_axi_wvalid && s_axi_wready) begin
                // Data handshake completed
                s_axi_wready       <= 1'b0;
                write_data_valid   <= 1'b1;
                write_data_latched <= s_axi_wdata;
            end else if (!s_axi_wready && s_axi_wvalid) begin
                // Data valid, assert ready
                s_axi_wready <= 1'b1;
            end else if (write_addr_valid && write_data_valid) begin
                // Both address and data received, ready for next transaction
                write_data_valid <= 1'b0;
                s_axi_wready     <= 1'b0;
            end
        end
    end

    // Write Response Channel (3/5)
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_bvalid <= 1'b0;
            s_axi_bresp  <= RESP_OKAY;
        end else begin
            if (s_axi_bvalid && s_axi_bready) begin
                // Response handshake completed
                s_axi_bvalid <= 1'b0;
            end else if (!s_axi_bvalid && write_addr_valid && write_data_valid) begin
                // Both address and data received, send response
                s_axi_bvalid <= 1'b1;
                s_axi_bresp  <= RESP_OKAY;
            end
        end
    end

    // Write Operation Logic 
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            tx_start <= 1'b0;
            tx_data  <= 8'h00;
        end else begin
            tx_start <= 1'b0;  // Default: no start

            // Process write when both address and data are valid
            if (write_addr_valid && write_data_valid && !s_axi_bvalid) begin
                case (write_addr_latched)
                    ADDR_TXDATA: begin
                        if (!tx_busy) begin
                            tx_data  <= write_data_latched[7:0];
                            tx_start <= 1'b1;
                        end
                        // If tx_busy, ignore the write (could also return error)
                    end

                    // Other addresses are read-only, ignore writes
                    default: begin
                        // Invalid write address 
                        s_axi_bresp  <= INVADD;
                    end
                endcase
            end
        end
    end
    

    // Read Address Channel (4/5)
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_arready           <= 1'b0;
            read_transaction_active <= 1'b0;
            read_addr_latched       <= 4'h0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                // Address handshake completed
                s_axi_arready           <= 1'b0;
                read_transaction_active <= 1'b1;
                read_addr_latched       <= read_addr_reg;
            end else if (!s_axi_arready && s_axi_arvalid) begin
                // Address valid, assert ready
                s_axi_arready <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
                // Read data handshake completed
                read_transaction_active <= 1'b0;
                s_axi_arready           <= 1'b0;
            end
        end
    end

    // Read Data Channel (5/5)
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_rdata  <= 32'h00000000;
            s_axi_rresp  <= RESP_OKAY;
            s_axi_rvalid <= 1'b0;
            rx_read      <= 1'b0;
        end else begin
            rx_read <= 1'b0;  // Default: no read acknowledge

            if (s_axi_rvalid && s_axi_rready) begin
                // Read handshake completed
                s_axi_rvalid <= 1'b0;
            end else if (!s_axi_rvalid && read_transaction_active) begin
                // Process read transaction
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= RESP_OKAY;

                case (read_addr_latched)
                    ADDR_RXDATA: begin
                        s_axi_rdata <= {24'h000000, rx_data};
                        rx_read     <= 1'b1;  // Clear rx_valid flag
                    end

                    ADDR_STATUS: begin
                        s_axi_rdata <= {30'h00000000, rx_valid, tx_busy};
                    end

                    default: begin
                        s_axi_rdata <= 32'h00000000;
                        s_axi_rresp <= RESP_SLVERR;  // Invalid address
                    end
                endcase
            end
        end
    end

endmodule
