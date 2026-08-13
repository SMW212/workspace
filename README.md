# TIA Portal SCL Automation Project

A SIEMENS TIA Portal project with PLC automation code written in SCL (Structured Control Language) for industrial control systems.

## Project Structure

```
src/
├── plc/              # Main PLC programs and logic
│   ├── main_program.scl
│   └── cycle_control.scl
├── scl/              # Reusable SCL functions and function blocks
│   ├── motor_control.scl
│   ├── sensor_handler.scl
│   └── communication.scl
└── data_blocks/      # Global data blocks (DB)
    ├── recipe_db.scl
    └── system_config.scl

docs/                # Documentation and specifications
.github/             # GitHub configuration and CI/CD
.vscode/             # VS Code settings and tasks
```

## Key Technologies

- **TIA Portal V17+**: SIEMENS automation platform
- **SCL (Structured Control Language)**: Primary programming language
- **S7-1200/S7-1500**: Target PLC families

## Development

See `.github/copilot-instructions.md` for AI-guided development patterns and conventions.
