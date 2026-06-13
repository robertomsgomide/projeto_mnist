#pragma once

#include <stddef.h>

void pc_protocol_handle_line(const char *line, char *response, size_t response_size);
