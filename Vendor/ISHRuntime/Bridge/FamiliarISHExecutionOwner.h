#include <stdint.h>

struct task;
uint64_t familiar_ish_assign_execution_owner(struct task *task);
void familiar_ish_discard_unstarted_task(struct task *task);
void familiar_ish_reap_execution_owner(uint64_t owner);
