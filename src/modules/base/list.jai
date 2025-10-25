Link_List :: struct(T: Type) {
    first: *Link_List_Node(T);
    last:  *Link_List_Node(T);
} 

Link_List_Node :: struct(T: Type) {
    next: *Link_List_Node(T);
    v: T;
};

link_list_push :: (list: *Link_List, node: *Link_List_Node) {
    if list.first == null {
        list.first = node; 
        list.last = node; 
        node.next = null;
    } else {
        list.last.next = node;
        list.last = node; 
        node.next = null;
    } 
} 


link_list_print :: (list: *Link_List) {
    sb: String_Builder;
    while list.first != list.last {
        if list.first  {
            print_to_builder(*sb,"% -> ", list.first.value);
            list.first = list.first.next;
        } 
    } 
    print_to_builder(*sb,"%", list.last.value);
    str := builder_to_string(*sb);
    print("%\n",str); 
} 

#import "Basic";



