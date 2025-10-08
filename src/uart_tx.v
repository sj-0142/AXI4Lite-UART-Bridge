module uart_tx #(
    parameter CLOCK_FREQ = 100000000,  // System clock frequency in Hz
    parameter BAUD_RATE  = 115200      // UART baud rate
)(
    input  wire       clk,
    input  wire       resetn,

    // Control interface
    input  wire       tx_start,        // Start transmission
    input  wire [7:0] tx_data,         // Data to transmit
    output reg        tx_busy,         // Transmitter busy flag

    // UART interface
    output reg        uart_tx          // UART TX line
);

    // Calculate clocks per bit
    localparam CLKS_PER_BIT = CLOCK_FREQ / BAUD_RATE;
    localparam COUNTER_WIDTH = $clog2(CLKS_PER_BIT);

    // State definitions
    localparam IDLE      = 3'b000;
    localparam START_BIT = 3'b001;
    localparam DATA_BITS = 3'b010;
    localparam STOP_BIT  = 3'b011;
    localparam CLEANUP   = 3'b100;

    // Internal registers
    reg [2:0] state;
    reg [COUNTER_WIDTH-1:0] bit_counter;
    reg [2:0] bit_index;
    reg [7:0] tx_data_reg;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state       <= IDLE;
            bit_counter <= {COUNTER_WIDTH{1'b0}};
            bit_index   <= 3'b000;
            tx_data_reg <= 8'h00;
            tx_busy     <= 1'b0;
            uart_tx     <= 1'b1;
        end else begin
            case (state)
                IDLE: begin
                    uart_tx     <= 1'b1;   // Idle high
                    tx_busy     <= 1'b0;
                    bit_counter <= {COUNTER_WIDTH{1'b0}};
                    bit_index   <= 3'b000;

                    if (tx_start) begin
                        tx_data_reg <= tx_data;
                        tx_busy     <= 1'b1;
                        state       <= START_BIT;
                    end
                end

                START_BIT: begin
                    uart_tx <= 1'b0;  // Start bit is low

                    if (bit_counter < (CLKS_PER_BIT - 1)) begin
                        bit_counter <= bit_counter + 1'b1;
                    end else begin
                        bit_counter <= {COUNTER_WIDTH{1'b0}};
                        state       <= DATA_BITS;
                    end
                end

                DATA_BITS: begin
                    uart_tx <= tx_data_reg[bit_index];  // Output current bit

                    if (bit_counter < (CLKS_PER_BIT - 1)) begin
                        bit_counter <= bit_counter + 1'b1;
                    end else begin
                        bit_counter <= {COUNTER_WIDTH{1'b0}};

                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= 3'b000;
                            state     <= STOP_BIT;
                        end
                    end
                end

                STOP_BIT: begin
                    uart_tx <= 1'b1;  // Stop bit is high

                    if (bit_counter < (CLKS_PER_BIT - 1)) begin
                        bit_counter <= bit_counter + 1'b1;
                    end else begin
                        bit_counter <= {COUNTER_WIDTH{1'b0}};
                        state       <= CLEANUP;
                    end
                end

                CLEANUP: begin
                    tx_busy <= 1'b0;
                    state   <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

