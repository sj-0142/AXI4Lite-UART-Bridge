module uart_rx #(
    parameter CLOCK_FREQ = 100000000,  // System clock frequency in Hz
    parameter BAUD_RATE  = 115200      // UART baud rate
)(
    input  wire       clk,
    input  wire       resetn,

    // UART interface
    input  wire       uart_rx,         // UART RX line

    // Control interface
    output reg  [7:0] rx_data,         // Received data
    output reg        rx_valid,        // Data valid flag
    input  wire       rx_read          // Read acknowledge (clears rx_valid)
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
    reg [7:0] rx_data_shift;

    // Double-register input to avoid metastability
    reg uart_rx_sync1;
    reg uart_rx_sync2;

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            uart_rx_sync1 <= 1'b1;
            uart_rx_sync2 <= 1'b1;
        end else begin
            uart_rx_sync1 <= uart_rx;
            uart_rx_sync2 <= uart_rx_sync1;
        end
    end

    always @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            state         <= IDLE;
            bit_counter   <= {COUNTER_WIDTH{1'b0}};
            bit_index     <= 3'b000;
            rx_data_shift <= 8'h00;
            rx_data       <= 8'h00;
            rx_valid      <= 1'b0;
        end else begin
            // Clear rx_valid when read
            if (rx_read) begin
                rx_valid <= 1'b0;
            end

            case (state)
                IDLE: begin
                    bit_counter   <= {COUNTER_WIDTH{1'b0}};
                    bit_index     <= 3'b000;
                    rx_data_shift <= 8'h00;

                    // Detect start bit (falling edge)
                    if (uart_rx_sync2 == 1'b0) begin
                        state <= START_BIT;
                    end
                end

                START_BIT: begin
                    // Wait for middle of start bit to verify it's still low
                    if (bit_counter == (CLKS_PER_BIT / 2)) begin
                        if (uart_rx_sync2 == 1'b0) begin
                            bit_counter <= {COUNTER_WIDTH{1'b0}};
                            state       <= DATA_BITS;
                        end else begin
                            state <= IDLE;  // False start bit
                        end
                    end else begin
                        bit_counter <= bit_counter + 1'b1;
                    end
                end

                DATA_BITS: begin
                    if (bit_counter < (CLKS_PER_BIT - 1)) begin
                        bit_counter <= bit_counter + 1'b1;
                    end else begin
                        bit_counter <= {COUNTER_WIDTH{1'b0}};
                        rx_data_shift[bit_index] <= uart_rx_sync2;  // Sample data bit

                        if (bit_index < 7) begin
                            bit_index <= bit_index + 1'b1;
                        end else begin
                            bit_index <= 3'b000;
                            state     <= STOP_BIT;
                        end
                    end
                end

                STOP_BIT: begin
                    if (bit_counter < (CLKS_PER_BIT - 1)) begin
                        bit_counter <= bit_counter + 1'b1;
                    end else begin
                        bit_counter <= {COUNTER_WIDTH{1'b0}};
                        // Check for valid stop bit
                        if (uart_rx_sync2 == 1'b1) begin
                            rx_data  <= rx_data_shift;
                            rx_valid <= 1'b1;
                        end
                        state <= CLEANUP;
                    end
                end

                CLEANUP: begin
                    state <= IDLE;
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

