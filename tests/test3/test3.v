module M #(parameter P=0) (input x);
endmodule

// Used to cause false positive due to invalid comment logic.
M #(.P(0)
) m (/*AUTOINST*/.x(0));

