fn main() {
    let prog = bars::reader::read("(-> 5 (add 3) (mul 2))").unwrap();
    println!("Original: {:#?}", prog);
    let expanded = bars::r#macro::expand_program(&prog).unwrap();
    println!("Expanded: {:#?}", expanded);
}
