PROFILE :: false;

#if PROFILE {
    PROFILE_SCOPE :: inline (scope_name: string, loc := #caller_location) #expand {
        // @TODO implement
    } 
} else {
    PROFILE_SCOPE :: inline (scope_name: string, loc := #caller_location) #expand {
        // no-op;
    } 
} 
