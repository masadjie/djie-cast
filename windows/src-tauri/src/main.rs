// Tanpa jendela konsol di Windows (release).
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

fn main() {
    djie_cast_lib::run()
}
