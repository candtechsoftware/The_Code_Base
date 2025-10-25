Corner :: enum  {
    INVALID;
    TOP_RIGHT; 
    TOP_LEFT;
    BOT_RIGHT;
    BOT_LEFT;
}

CORNER_COUNT :: #run enum_highest_value(Corner) + 1;

Axis :: enum { X; Y; Z; W; } 

Side :: enum { MIN; MAX; } 



#import "Basic";


