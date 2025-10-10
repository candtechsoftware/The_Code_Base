Rng2 :: union {
    struct {
        min, max: Vector2;
    };
    struct {  
        p0, p1:   Vector2;
    };
    struct { 
        x0, y0:   float; 
        x1, y1:   float;
    }; 
    v:            [2]Vector2;
};

make_rng2 :: (x0: float, y0: float, x1: float, y1: float) -> Rng2 {
    rng: Rng2;
    rng.min = .{x0, y0};
    rng.max = .{x1, y1};
    return rng;
}

 
    

    
