export type PostCommitTask = {
  name: string;
  promise: Promise<unknown>;
};

export async function settlePostCommitTasks(
  tasks: PostCommitTask[],
  onError: (taskName: string, error: unknown) => void = (taskName, error) => {
    console.error(`[post-commit] ${taskName} failed`, error);
  },
) {
  const results = await Promise.allSettled(tasks.map((task) => task.promise));
  results.forEach((result, index) => {
    if (result.status === 'rejected') {
      onError(tasks[index].name, result.reason);
    }
  });
}
