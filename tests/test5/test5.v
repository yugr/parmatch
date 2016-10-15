module M #(parameter A, parameter B) (input x, output y);
endmodule

// Tool should ignore second 'M'
M #(.A(A), .B(B)) M(.x(0));

