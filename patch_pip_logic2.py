import re

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoWin/src/main.rs", "r") as f:
    content = f.read()

# Replace broken patch
bad_ui = """        if self.pip {
            if ui.rect_contains_pointer(ui.max_rect()) && ui.input(|i| i.pointer.primary_down()) {
                if !ctx.wants_pointer_input() {
                    ctx.send_viewport_cmd(egui::ViewportCommand::BeginDrag);
                }
            }
        }"""

good_ui = """        if self.pip {
            if ui.rect_contains_pointer(ui.max_rect()) && ui.input(|i| i.pointer.primary_down()) {
                if !ctx.egui_wants_pointer_input() {
                    ctx.send_viewport_cmd(egui::ViewportCommand::StartDrag);
                }
            }
        }"""
content = content.replace(bad_ui, good_ui)

bad_shortcut = """                egui::Key::P => {
                    self.pip = !self.pip;
                    ctx.send_viewport_cmd(egui::ViewportCommand::AlwaysOnTop(self.pip));
                    ctx.send_viewport_cmd(egui::ViewportCommand::Decorations(!self.pip));
                    if self.pip {
                        self.lista_aberta = false;
                        ctx.send_viewport_cmd(egui::ViewportCommand::InnerSize([400.0, 225.0].into()));
                    } else {
                        ctx.send_viewport_cmd(egui::ViewportCommand::InnerSize([1280.0, 720.0].into()));
                    }
                }"""

good_shortcut = """                egui::Key::P => {
                    self.pip = !self.pip;
                    let nivel = if self.pip { egui::viewport::WindowLevel::AlwaysOnTop } else { egui::viewport::WindowLevel::Normal };
                    ctx.send_viewport_cmd(egui::ViewportCommand::WindowLevel(nivel));
                    ctx.send_viewport_cmd(egui::ViewportCommand::Decorations(!self.pip));
                    if self.pip {
                        self.lista_aberta = false;
                        ctx.send_viewport_cmd(egui::ViewportCommand::InnerSize([400.0, 225.0].into()));
                    } else {
                        ctx.send_viewport_cmd(egui::ViewportCommand::InnerSize([1280.0, 720.0].into()));
                    }
                }"""
content = content.replace(bad_shortcut, good_shortcut)

with open("/Volumes/SSD 1TB/DEV/Saimo/SaimoWin/src/main.rs", "w") as f:
    f.write(content)

