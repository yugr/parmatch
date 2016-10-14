module M #(A, B) (x, y);
endmodule

// Tool should ignore second 'M'
M #(.A(A), .B(B)) M(.x(0), .y(0));

