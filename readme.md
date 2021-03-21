# Laravel Permissions

Lighning-fast command line tool that sets the correct permissions on a Laravel project in a Linux environment. This is an opinionated tool, and assumes that you follow the domain-user approach to virtual hosts. That is, each virtual host has its own system user.

## Run with V

```shell
$ v run laravel_permissions.v
```

1. Type in the owner domain-user
2. Type in the web server user group (defaults to www-data)
3. Watch it fly:

```
running preflight checks
os supported
running as root
preflight checks complete

answer the following prompts, or type exit, quit, or q to quit.
? owner user (domain-user) required domain.com
? group (web-server user) www-data
→ adding owner to web-server group…
→ applying group and owner to /home/domain.com/www…
→ setting file permissions to 660…
→ setting directory permissions to 2770…
→ setting web-server group on storage and bootstrap/cache directories…
→ setting ug+rwx permissions on storage and bootstrap/cache directories…
done.
```

## Build for Production

```shell
$ v -prod -os linux
```

This will create a binary called `laravel_permissions`.

You can now dump this binary on your server however you see fit.

## Todo

- [x] Get the domain-user home directory instead of hard-coding to `/home/$user`
- [x] Ask for the document root instead of hard-coding to `www`
- [ ] - `swap out the is_dir check for a validator once closure support has been added to vlang.`
- [ ] Allow environment variables or vargs to set permission modes instead of hard-coding to `640` and `2770` (although, this might not be necessary)
