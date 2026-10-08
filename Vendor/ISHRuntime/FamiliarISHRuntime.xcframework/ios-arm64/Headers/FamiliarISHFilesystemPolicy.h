#include <stdbool.h>

// Enabled only while a single guest owner holds the current Project mounts.
// Native preparation and mount setup run outside this scope.
bool familiar_ish_workspace_isolation_enabled(void);
