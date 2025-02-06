top_root: []const u8 = "┌───┐", // For nodes with no parent.
top: []const u8 = "┌─┴─┐", // For nodes with a parent.
bottom_connector: []const u8 = "└─┬─┘", // For nodes that have children (or are not the last).
bottom_leaf: []const u8 = "└───┘", // For leaf nodes or the last node in a branch.
middle: []const u8 = "│   │",
vertical: []const u8 = "   │",
// ... (other characters if needed)
