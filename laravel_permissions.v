import os
import cli
import term

// using []string is temporary until vlang supports closures with parent-scope support.
fn valid_string_prompt(input string, using []string) (bool, string) {
  return true, ''
}

type StringValidationCallback = fn (input string, using []string) (bool, string)

pub struct StringPrompt {
  message string [required]
  default string
  required bool
  using []string
  validator StringValidationCallback = valid_string_prompt
}

pub struct Instruction {
  label string [required]
  command string [required]
}

pub fn ask(prompt StringPrompt) string {
  default_str := if prompt.default == '' { 'required' } else { prompt.default }
  input := os.input(term.yellow('? ' + prompt.message) + term.dim(' ($default_str) → '))

  if prompt.required && input == '' {
    eprintln(term.red('  input is required'))
    return ask(prompt)
  }

  mut output := if input.len > 0 { input } else { prompt.default }
  output = output.trim_space()
  valid, err := prompt.validator(output, prompt.using)

  if output in ['exit', 'quit', 'q'] {
    eprintln(term.yellow('intent: $output, quitting'))
    exit(0)
  }

  if !valid {
    eprintln(term.red('  input is invalid: $err'))
    return ask(prompt)
  }

  return output
}

pub fn preflight() {
  println(term.bright_blue('running preflight checks'))

  ensure_supported_user_os()
  ensure_running_as_root()

  println(term.green('preflight checks complete'))
}

pub fn ensure_supported_user_os() {
  println(term.dim('ensuring os supported'))

  user_os := os.user_os()

  if user_os.trim_space() != 'linux' {
    eprintln(term.red('$user_os is not supported'))
    exit(1)
  }

  term.cursor_up(1)
  term.erase_line_clear()

  println(term.bright_green('os supported'))
}

pub fn ensure_running_as_root() {
  println(term.dim('ensuring running as root'))

  result := os.execute_or_panic('id -u')

  if result.output.trim_space() != '0' {
    eprintln(term.red('must be running as root, quitting'))
    exit(1)
  }

  term.cursor_up(1)
  term.erase_line_clear()

  println(term.bright_green('running as root'))
}

fn main() {
  mut app := cli.Command{
    name: 'laravel_permissions'
    description: 'Sets the correct permissions on a Laravel project.'
    version: '1.0.0'
    disable_flags: true
    execute: run
  }
  app.parse(os.args)
}

pub fn run(command cli.Command) {
  preflight()

  println('')
  println(term.dim('answer the following prompts, or type exit, quit, or q to quit.'))

  user_validator := fn (input string, using []string) (bool, string) {
    return os.execute('id -un $input').exit_code == 0, 'invalid username, does not exist'
  }

  owner := ask(
    message: 'owner user'
    required: true
    validator: user_validator
  )

  group := ask(
    message: 'group (web-server user)'
    default: 'www-data'
    validator: user_validator
  )

  homedir := ask(
    message: 'home directory (relative to server root)'
    default: 'home'
    validator: fn (input string, using []string) (bool, string) {
      return os.is_dir('/' + input.trim_left('/')), 'invalid home directory, does not exist'
    }
  )

  www := ask(
    message: 'public/docroot directory (relative to /$homedir/$owner)'
    default: 'www'
    using: ['/$homedir/$owner/']
    validator: fn (input string, using []string) (bool, string) {
      println(using[0] + input.trim('/'))
      return os.is_dir(using[0] + input.trim('/')), 'invalid public/docroot directory, does not exist'
    }
  ).trim('/')

  path := '/$homedir/$owner/$www'

  instructions := [
    Instruction{'adding owner to web-server group…', 'usermod -a -G $group $owner'},
    Instruction{'applying group and owner to $path…', 'chown -R $owner:$group $path'},
    Instruction{'setting file permissions to 660…', 'find $path -type f -exec chmod 660 {} +'},
    Instruction{'setting directory permissions to 2770…', 'find $path -type d -exec chmod 2770 {} +'},
    Instruction{'setting web-server group on storage and bootstrap/cache directories…', 'chgrp -R $group $path/storage $path/bootstrap/cache'},
    Instruction{'setting ug+rwx permissions on storage and bootstrap/cache directories…', 'chmod -R ug+rwx $path/storage $path/bootstrap/cache'},
  ]

  for instruction in instructions {
    println(term.bright_blue('→ $instruction.label ($instruction.command)'))
    os.execute_or_panic(instruction.command)
  }

  println(term.green('done.'))
}
