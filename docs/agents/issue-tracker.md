# GitHub Issues

在 Win-Dock 仓库目录内使用 `gh`。用 `gh repo view --json nameWithOwner --jq .nameWithOwner` 核对目标为 `XuMJ0220/Win-Dock`。

## Issues

- 用 `gh issue create --title "$title" --body-file "$bodyFile"` 发布规格或任务单。
- 用 `gh issue view $number --json number,title,body,labels,comments` 读取任务单和讨论。
- 用 `gh issue list --state open --json number,title,body,labels,comments` 列出待处理任务单。按任务增加 `--label` 或调整 `--state`。
- 用 `gh issue comment $number --body "$comment"` 回复，用 `gh issue edit $number --add-label "$label"` 或 `--remove-label "$label"` 调整标签。
- 需要附关闭说明时先评论，再用 `gh issue close $number` 关闭。

## Sub-issues and dependencies

- 用 `gh api "repos/{owner}/{repo}/issues/$number" --jq .id` 读取 Issue 的数字数据库 ID。
- 用 `gh api --method POST "repos/{owner}/{repo}/issues/$parent/sub_issues" -F "sub_issue_id=$childId"` 把子 Issue 加到父 Issue。
- 用 `gh api --method POST "repos/{owner}/{repo}/issues/$child/dependencies/blocked_by" -F "issue_id=$blockerId"` 记录阻塞关系。
- 用 `gh api --paginate "repos/{owner}/{repo}/issues/$child/dependencies/blocked_by" --jq '.[] | [.number, .state] | @tsv'` 列出阻塞项。所有阻塞项关闭后即可启动任务。
- 原生功能不可用时，在正文开头用 `Part of #<parent>` 或 `Blocked by: #<blocker>` 记录关系。

## Pull requests as a triage surface

**PRs as a request surface: no.**

启用后，用 `gh pr view` 和 `gh pr diff` 读取外部 PR，再用 `gh pr comment`、`gh pr edit` 和 `gh pr close` 分类处理。Issue 与 PR 共享编号，先用 `gh pr view $number` 判断类型，再按类型读取。

## Wayfinding operations

- 用带 `wayfinder:map` 标签的 Issue 记录笔记、已定事项和待确认问题。
- 将票据作为子 Issue 关联，使用 `wayfinder:research`、`wayfinder:prototype`、`wayfinder:grilling` 或 `wayfinder:task` 标记类型。
- 用 `gh api --paginate "repos/{owner}/{repo}/issues/$parent/sub_issues"` 读取子 Issue。按地图顺序选择第一个开放、未分配且无未关闭阻塞项的任务单。
- 用 `gh issue edit $number --add-assignee '@me'` 认领。完成时留言、关闭，并把结果和链接写回地图。
