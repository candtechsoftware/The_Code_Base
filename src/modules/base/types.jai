Corner :: enum  {
    INVALID;
    TOP_RIGHT; 
    TOP_LEFT;
    BOT_RIGHT;
    BOT_LEFT;
}

CORNER_COUNT :: #run enum_highest_value(Corner) + 1;


#import "Basic";


