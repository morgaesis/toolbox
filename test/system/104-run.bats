#!/usr/bin/env bats

load 'libs/bats-support/load'
load 'libs/bats-assert/load'
load 'libs/helpers'

setup() {
  _setup_environment
  cleanup_containers
}

teardown() {
  cleanup_containers
}

@test "run: Smoke test with true(1)" {
  create_default_container

  run $TOOLBOX run true

  assert_success
  assert_output ""
}

@test "run: Smoke test with false(1)" {
  create_default_container

  run -1 $TOOLBOX run false

  assert_failure
  assert_output ""
}

@test "run: Ensure that a login shell is used to invoke the command" {
  create_default_container

  cp "$HOME"/.bash_profile "$HOME"/.bash_profile.orig
  echo "echo \"~/.bash_profile read\"" >>"$HOME"/.bash_profile

  run $TOOLBOX run true

  mv "$HOME"/.bash_profile.orig "$HOME"/.bash_profile

  assert_success
  assert_line --index 0 "~/.bash_profile read"
  assert [ ${#lines[@]} -eq 1 ]
}

@test "run: 'echo \"Hello World\"' inside the default container" {
  create_default_container

  run $TOOLBOX --verbose run echo "Hello World"

  assert_success
  assert_line --index $((${#lines[@]}-1)) "Hello World"
}

@test "run: 'echo \"Hello World\"' inside a restarted container" {
  create_container running

  start_container running
  stop_container running

  run $TOOLBOX --verbose run --container running echo "Hello World"

  assert_success
  assert_line --index $((${#lines[@]}-1)) "Hello World"
}

@test "run: 'sudo id' inside the default container" {
  create_default_container

  output="$($TOOLBOX --verbose run sudo id 2>$BATS_TMPDIR/stderr)"
  status="$?"

  echo "# stderr"
  cat $BATS_TMPDIR/stderr
  echo "# stdout"
  echo $output

  assert_success
  assert_output --partial "uid=0(root)"
}

@test "run: Ensure that /run/.containerenv exists" {
  create_default_container

  run --separate-stderr $TOOLBOX run cat /run/.containerenv

  assert_success
  assert [ ${#lines[@]} -gt 0 ]
  assert [ ${#stderr_lines[@]} -eq 0 ]
}

@test "run: Ensure that /run/.toolboxenv exists" {
  create_default_container

  run --separate-stderr $TOOLBOX run test -f /run/.toolboxenv

  assert_success
  assert [ ${#lines[@]} -eq 0 ]
  assert [ ${#stderr_lines[@]} -eq 0 ]
}

@test "run: Ensure that the default container is used" {
  run echo "$name"

  assert_success
  assert_output ""

  local default_container_name="$(get_system_id)-toolbox-$(get_system_version)"
  create_default_container
  create_container other-container

  run --separate-stderr $TOOLBOX run cat /run/.containerenv

  assert_success
  assert [ ${#lines[@]} -gt 0 ]
  assert [ ${#stderr_lines[@]} -eq 0 ]

  source <(echo "$output")
  run echo "$name"

  assert_success
  assert_output "$default_container_name"
}

@test "run: Ensure that a specific container is used" {
  run echo "$name"

  assert_success
  assert_output ""

  local default_container_name="$(get_system_id)-toolbox-$(get_system_version)"
  create_default_container
  create_container other-container

  run --separate-stderr $TOOLBOX run --container other-container cat /run/.containerenv

  assert_success
  assert [ ${#lines[@]} -gt 0 ]
  assert [ ${#stderr_lines[@]} -eq 0 ]

  source <(echo "$output")
  run echo "$name"

  assert_success
  assert_output "other-container"
}

@test "run: Ensure that $HOME is used as a fallback working directory" {
  local default_container_name="$(get_system_id)-toolbox-$(get_system_version)"
  create_default_container

  pushd /etc/kernel
  run --separate-stderr $TOOLBOX run pwd
  popd

  assert_success
  assert_line --index 0 "$HOME"
  assert [ ${#lines[@]} -eq 1 ]
  lines=("${stderr_lines[@]}")
  assert_line --index $((${#stderr_lines[@]}-2)) "Error: directory /etc/kernel not found in container $default_container_name"
  assert_line --index $((${#stderr_lines[@]}-1)) "Using $HOME instead."
  assert [ ${#stderr_lines[@]} -gt 2 ]
}

@test "run: Pass down 1 additional file descriptor" {
  create_default_container

  # File descriptors 3 and 4 are reserved by Bats.
  run --separate-stderr $TOOLBOX run --preserve-fds 3 readlink /proc/self/fd/5 5>/dev/null

  assert_success
  assert_line --index 0 "/dev/null"
  assert [ ${#lines[@]} -eq 1 ]
  assert [ ${#stderr_lines[@]} -eq 0 ]
}

@test "run: Try the non-existent default container with none other present" {
  local default_container_name="$(get_system_id)-toolbox-$(get_system_version)"

  run --separate-stderr $TOOLBOX run true

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: container $default_container_name not found"
  assert_line --index 1 "Use the 'create' command to create a toolbox."
  assert_line --index 2 "Run 'toolbox --help' for usage."
  assert [ ${#stderr_lines[@]} -eq 3 ]
}

@test "run: Try the non-existent default container with another present" {
  local default_container_name="$(get_system_id)-toolbox-$(get_system_version)"

  create_container other-container

  run --separate-stderr $TOOLBOX run true

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: container $default_container_name not found"
  assert_line --index 1 "Use the 'create' command to create a toolbox."
  assert_line --index 2 "Run 'toolbox --help' for usage."
  assert [ ${#stderr_lines[@]} -eq 3 ]
}

@test "run: Try a specific non-existent container with another present" {
  create_container other-container

  run --separate-stderr $TOOLBOX run --container wrong-container true

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: container wrong-container not found"
  assert_line --index 1 "Use the 'create' command to create a toolbox."
  assert_line --index 2 "Run 'toolbox --help' for usage."
  assert [ ${#stderr_lines[@]} -eq 3 ]
}

@test "run: Try an unsupported distribution" {
  local distro="foo"

  run --separate-stderr $TOOLBOX --assumeyes run --distro "$distro" ls

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: invalid argument for '--distro'"
  assert_line --index 1 "Distribution $distro is unsupported."
  assert_line --index 2 "Run 'toolbox --help' for usage."
  assert [ ${#stderr_lines[@]} -eq 3 ]
}

@test "run: Try Fedora with an invalid release" {
  run --separate-stderr $TOOLBOX run --distro fedora --release foobar ls

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: invalid argument for '--release'"
  assert_line --index 1 "The release must be a positive integer."
  assert_line --index 2 "Run 'toolbox --help' for usage."
  assert [ ${#stderr_lines[@]} -eq 3 ]

  run --separate-stderr $TOOLBOX run --distro fedora --release -3 ls

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: invalid argument for '--release'"
  assert_line --index 1 "The release must be a positive integer."
  assert_line --index 2 "Run 'toolbox --help' for usage."
  assert [ ${#stderr_lines[@]} -eq 3 ]
}

@test "run: Try RHEL with an invalid release" {
  run --separate-stderr $TOOLBOX run --distro rhel --release 8 ls

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: invalid argument for '--release'"
  assert_line --index 1 "The release must be in the '<major>.<minor>' format."
  assert_line --index 2 "Run 'toolbox --help' for usage."
  assert [ ${#stderr_lines[@]} -eq 3 ]

  run --separate-stderr $TOOLBOX run --distro rhel --release 8.2foo ls

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: invalid argument for '--release'"
  assert_line --index 1 "The release must be in the '<major>.<minor>' format."
  assert_line --index 2 "Run 'toolbox --help' for usage."
  assert [ ${#stderr_lines[@]} -eq 3 ]

  run --separate-stderr $TOOLBOX run --distro rhel --release -2.1 ls

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: invalid argument for '--release'"
  assert_line --index 1 "The release must be a positive number."
  assert_line --index 2 "Run 'toolbox --help' for usage."
  assert [ ${#stderr_lines[@]} -eq 3 ]
}

@test "run: Try a non-default distro without a release" {
  local distro="fedora"
  local system_id="$(get_system_id)"

  if [ "$system_id" = "fedora" ]; then
    distro="rhel"
  fi

  run --separate-stderr $TOOLBOX run --distro "$distro" ls

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: option '--release' is needed"
  assert_line --index 1 "Distribution $distro doesn't match the host."
  assert_line --index 2 "Run 'toolbox --help' for usage."
  assert [ ${#stderr_lines[@]} -eq 3 ]
}

@test "run: Smoke test with 'exit 2'" {
  create_default_container

  run -2 $TOOLBOX run /bin/sh -c 'exit 2'
  assert_failure
  assert_output ""
}

@test "run: Pass down 1 invalid file descriptor" {
  local default_container_name="$(get_system_id)-toolbox-$(get_system_version)"
  create_default_container

  # File descriptors 3 and 4 are reserved by Bats.
  run -125 --separate-stderr $TOOLBOX run --preserve-fds 3 readlink /proc/self/fd/5

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "Error: file descriptor 5 is not available - the preserve-fds option requires that file descriptors must be passed"
  assert_line --index 1 "Error: failed to invoke 'podman exec' in container $default_container_name"
  assert [ ${#stderr_lines[@]} -eq 2 ]
}

@test "run: Try /etc as a command" {
  create_default_container

  run -126 --separate-stderr $TOOLBOX run /etc

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "bash: line 1: /etc: Is a directory"
  assert_line --index 1 "bash: line 1: exec: /etc: cannot execute: Is a directory"
  assert_line --index 2 "Error: failed to invoke command /etc in container $(get_latest_container_name)"
  assert [ ${#stderr_lines[@]} -eq 3 ]
}

@test "run: Try a non-existent command" {
  local cmd="non-existent-command"

  create_default_container

  run -127 --separate-stderr $TOOLBOX run $cmd

  assert_failure
  assert [ ${#lines[@]} -eq 0 ]
  lines=("${stderr_lines[@]}")
  assert_line --index 0 "bash: line 1: exec: $cmd: not found"
  assert_line --index 1 "Error: command $cmd not found in container $(get_latest_container_name)"
  assert [ ${#stderr_lines[@]} -eq 2 ]
}
