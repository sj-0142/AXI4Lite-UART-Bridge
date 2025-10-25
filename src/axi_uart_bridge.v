// AUTHOR: SANJAY JAYARAMAN
// Register Map:
// 0x00: TXDATA (write-only) - Writing triggers UART transmit
// 0x04: RXDATA (read-only)  - Reading gives last received byte, clears rx_valid
// 0x08: STATUS (read-only)  - bit[0] = tx_busy, bit[1] = rx_valid


module axi_uart_bridge #(
    parameter CLOCK_FREQ = 100000000,  
    parameter BAUD_RATE  = 115200,     
    parameter AXI_ADDR_WIDTH = 32,     
    parameter AXI_DATA_WIDTH = 32      h
)(
    
    input  wire                          clk,
    input  wire                          resetn,

    
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_awaddr,
    input  wire                          s_axi_awvalid,
    output reg                           s_axi_awready,

    
    input  wire [AXI_DATA_WIDTH-1:0]    s_axi_wdata,
    input  wire                          s_axi_wvalid,
    output reg                           s_axi_wready,

    
    output reg  [1:0]                    s_axi_bresp,
    output reg                           s_axi_bvalid,
    input  wire                          s_axi_bready,

    
    input  wire [AXI_ADDR_WIDTH-1:0]    s_axi_araddr,
    input  wire                          s_axi_arvalid,
    output reg                           s_axi_arready,

    
    output reg  [AXI_DATA_WIDTH-1:0]    s_axi_rdata,
    output reg  [1:0]                    s_axi_rresp,
    output reg                           s_axi_rvalid,
    input  wire                          s_axi_rready,

    
    output wire                          uart_tx,
    input  wire                          uart_rx
);

    
    localparam ADDR_TXDATA = 4'h0;  // 0x00
    localparam ADDR_RXDATA = 4'h1;  // 0x04
    localparam ADDR_STATUS = 4'h2;  // 0x08

    
    localparam RESP_OKAY   = 2'b00;
    localparam RESP_SLVERR = 2'b10;
    localparam TXBUSY = 2'b01;
    localparam INVADD = 2'b11;

    
    wire [3:0] write_addr_reg;
    wire [3:0] read_addr_reg;

    
    reg        tx_start;
    reg  [7:0] tx_data;
    wire       tx_busy;
    wire [7:0] rx_data;
    wire       rx_valid;
    reg        rx_read;

    
    reg        write_addr_valid;
    reg        write_data_valid;
    reg [3:0]  write_addr_latched;
    reg [31:0] write_data_latched;

    
    reg        read_transaction_active;
    reg [3:0]  read_addr_latched;

    
    assign write_addr_reg = s_axi_awaddr[5:2];
    assign read_addr_reg  = s_axi_araddr[5:2];
    
   
    
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


    


    // Write Address Channel (1/5)
    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            s_axi_awready      <= 1'b0;
            write_addr_valid   <= 1'b0;
            write_addr_latched <= 4'h0;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                s_axi_awready      <= 1'b0;
                write_addr_valid   <= 1'b1;
                write_addr_latched <= write_addr_reg;
            end else if (!s_axi_awready && s_axi_awvalid) begin
                s_axi_awready <= 1'b1;
            end else if (write_addr_valid && write_data_valid) begin
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
                s_axi_wready       <= 1'b0;
                write_data_valid   <= 1'b1;
                write_data_latched <= s_axi_wdata;
            end else if (!s_axi_wready && s_axi_wvalid) begin
                s_axi_wready <= 1'b1;
            end else if (write_addr_valid && write_data_valid) begin
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
                s_axi_bvalid <= 1'b0;
            end else if (!s_axi_bvalid && write_addr_valid && write_data_valid) begin
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
            tx_start <= 1'b0;  
            if (write_addr_valid && write_data_valid && !s_axi_bvalid) begin
                case (write_addr_latched)
                    ADDR_TXDATA: begin
                        if (!tx_busy) begin
                            tx_data  <= write_data_latched[7:0];
                            tx_start <= 1'b1;
                        end
                        else
                        
                        s_axi_bresp <= TXBUSY;
                    end
                    
                    default: begin 
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
                s_axi_arready           <= 1'b0;
                read_transaction_active <= 1'b1;
                read_addr_latched       <= read_addr_reg;
            end else if (!s_axi_arready && s_axi_arvalid) begin
                s_axi_arready <= 1'b1;
            end else if (s_axi_rvalid && s_axi_rready) begin
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
            rx_read <= 1'b0;  

            if (s_axi_rvalid && s_axi_rready) begin
                s_axi_rvalid <= 1'b0;
            end else if (!s_axi_rvalid && read_transaction_active) begin
                s_axi_rvalid <= 1'b1;
                s_axi_rresp  <= RESP_OKAY;

                case (read_addr_latched)
                    ADDR_RXDATA: begin
                        s_axi_rdata <= {24'h000000, rx_data};
                        rx_read     <= 1'b1;  
                    end

                    ADDR_STATUS: begin
                        s_axi_rdata <= {30'h00000000, rx_valid, tx_busy};
                    end

                    default: begin
                        s_axi_rdata <= 32'h00000000;
                        s_axi_rresp <= RESP_SLVERR;  
                    end
                endcase
            end
        end
    end

endmodule
