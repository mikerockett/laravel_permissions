import os { args, execute, execute_or_panic, input, user_os }
import cli { Command }
import term
import regex

const (
	fqdn_max_label_length = 63
	fqdn_re_base          = r'^[-a-zA-Z0-9]+$'
	fqdn_re_tld           = r'^(([a-zA-Z]{2,})|(xn[-a-zA-Z0-9]{2,}))$'
)

fn valid_string_prompt(input string) (bool, string) {
	return true, ''
}

pub fn regex_valid(re_query string) bool {
	regex.regex_opt(re_query) or { return false }
	return true
}

pub fn regex_match(val string, re_query string) bool {
	if !regex_valid(re_query) {
		eprintln('Regex $re_query is invalid.')
		exit(1)
	}
	mut re := regex.regex_opt(re_query) or { return false }
	start, _ := re.match_string(val)
	return start != regex.no_match_found
}

pub fn validate_fqdn(hostname string) bool {
	parts := hostname.split('.')
	for part in parts {
		if part.len > fqdn_max_label_length {
			return false
		}
	}
	if parts.len < 2 {
		return false
	}
	tld := parts.last()
	if !regex_match(tld, fqdn_re_tld) {
		return false
	}
	for part in parts {
		if !regex_match(part, fqdn_re_base) {
			return false
		}
		if part[0] == `-` || part[part.len - 1] == `-` {
			return false
		}
	}
	return true
}

type StringValidationCallback = fn (input string) (bool, string)

pub struct StringPrompt {
	message   string                   [required]
	default   string
	required  bool
	validator StringValidationCallback = valid_string_prompt
}

pub fn ask(prompt StringPrompt) string {
	default_str := if prompt.default == '' { 'required' } else { prompt.default }
	input := input(term.yellow('? ') + prompt.message + term.dim(' $default_str '))
	if prompt.required && input == '' {
		eprintln(term.red('  input is required'))
		return ask(prompt)
	}
	mut output := if input.len > 0 { input } else { prompt.default }
	output = output.trim_space()
	valid, err := prompt.validator(output)
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
	user_os := user_os()
	allowed := $if prod { ['linux'] } $else { ['linux', 'macos'] }
	if user_os.trim_space() !in allowed {
		eprintln(term.red('$user_os is not supported'))
		exit(1)
	}
	term.cursor_up(1)
	term.erase_line_clear()
	println(term.bright_green('os supported'))
}

pub fn ensure_running_as_root() {
	println(term.dim('ensuring running as root'))
	result := execute_or_panic('id -u')
	allowed := $if prod { ['0'] } $else { ['0', '501'] }
	if result.output.trim_space() !in allowed {
		eprintln(term.red('must be running as root, quitting'))
		exit(1)
	}
	term.cursor_up(1)
	term.erase_line_clear()
	println(term.bright_green('running as root'))
}

fn main() {
	mut app := Command{
		name: 'laravel_permissions'
		description: 'Sets the correct permissions on a Laravel project.'
		version: '1.0.0'
		disable_flags: true
		execute: run
	}
	app.parse(args)
}

pub fn run(command Command) {
	preflight()

	println(term.dim('answer the following prompts, or type exit, quit, or q to quit.'))

	owner := ask(
		message: 'owner user (domain-user)'
		required: true
		validator: fn (input string) (bool, string) {
			return validate_fqdn(input) && execute('id -un $input').exit_code == 0, 'invalid domain-based username (does not exist or is malformed)'
		}
	)

	group := ask(
		message: 'group (web-server user)'
		default: 'www-data'
		validator: fn (input string) (bool, string) {
			return execute('id -un $input').exit_code == 0, 'invalid username (does not exist)'
		}
	)

	www := '/home/$owner/www'
	println(term.bright_blue('→ adding owner to web-server group…'))
	execute_or_panic('usermod -a -G $group $owner')

	println(term.bright_blue('→ applying group and owner to $www…'))
	execute_or_panic('chown -R $owner:$group $www')

	println(term.bright_blue('→ setting file permissions to 660…'))
	execute_or_panic('find $www -type f -exec chmod 660 {} +')

	println(term.bright_blue('→ setting directory permissions to 2770…'))
	execute_or_panic('find $www -type d -exec chmod 2770 {} +')

	println(term.bright_blue('→ setting web-server group on storage and bootstrap/cache directories…'))
	execute_or_panic('chgrp -R $group $www/storage $www/bootstrap/cache')

	println(term.bright_blue('→ setting ug+rwx permissions on storage and bootstrap/cache directories…'))
	execute_or_panic('chmod -R ug+rwx $www/storage $www/bootstrap/cache')

	println(term.green('done.'))
}
