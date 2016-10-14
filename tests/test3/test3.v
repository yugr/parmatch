module M #(parameter P=0) (x);
endmodule

// Used to cause false positive due to invalid comment logic.
M #(.P(0)
) m (/*AUTOINST*/.x, .y);

