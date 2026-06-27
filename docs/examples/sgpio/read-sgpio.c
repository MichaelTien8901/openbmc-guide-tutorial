// SPDX-License-Identifier: Apache-2.0
//
// Minimal libgpiod reader for an SGPIO input line.
//
// SGPIO needs no special libgpiod calls -- this is the ordinary named-line read
// pattern. Resolving by name means you do not care which gpiochip the SGPIO
// controller landed on, and you read the INPUT (even) half of a hardware line.
//
//   gcc read-sgpio.c -lgpiod -o read-sgpio && ./read-sgpio
//
// Built/tested against libgpiod v1 (gpiod_line_find / gpiod_line_request_input).

#include <gpiod.h>
#include <stdio.h>

int main(void)
{
	const char *name = "CPU1_THERMTRIP";

	/* Find the line by name across every gpiochip on the system. */
	struct gpiod_line *line = gpiod_line_find(name);
	if (!line) {
		fprintf(stderr, "%s not found (check gpio-line-names)\n", name);
		return 1;
	}

	if (gpiod_line_request_input(line, "sgpio-reader") < 0) {
		perror("gpiod_line_request_input");
		return 1;
	}

	int value = gpiod_line_get_value(line); /* even/input line: read-only */
	if (value < 0) {
		perror("gpiod_line_get_value");
		gpiod_line_release(line);
		return 1;
	}

	printf("%s = %d\n", name, value);

	gpiod_line_release(line);
	return 0;
}
</content>
