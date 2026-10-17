import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoWin/src/main.rs", "r") as f:
    content = f.read()

# Add dragging logic to App::ui
ui_function_old = """        foto_de_teste(self, ctx);
        tela::desenhar(self, ui);"""

ui_function_new = """        foto_de_teste(self, ctx);
        tela::desenhar(self, ui);

        if self.pip {
            if ui.rect_contains_pointer(ui.max_rect()) && ui.input(|i| i.pointer.primary_down()) {
                if !ctx.wants_pointer_input() {
                    ctx.send_viewport_cmd(egui::ViewportCommand::BeginDrag);
                }
            }
        }"""
content = content.replace(ui_function_old, ui_function_new)

# Add Key::P shortcut handling
shortcut_old = """                egui::Key::Tab => {"""

shortcut_new = """                egui::Key::P => {
                    self.pip = !self.pip;
                    ctx.send_viewport_cmd(egui::ViewportCommand::AlwaysOnTop(self.pip));
                    ctx.send_viewport_cmd(egui::ViewportCommand::Decorations(!self.pip));
                    if self.pip {
                        self.lista_aberta = false;
                        ctx.send_viewport_cmd(egui::ViewportCommand::InnerSize([400.0, 225.0].into()));
                    } else {
                        ctx.send_viewport_cmd(egui::ViewportCommand::InnerSize([1280.0, 720.0].into()));
                    }
                }
                egui::Key::Tab => {"""
content = content.replace(shortcut_old, shortcut_new)

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoWin/src/main.rs", "w") as f:
    f.write(content)

