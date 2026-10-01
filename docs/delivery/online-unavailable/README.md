# Deferred online groups source

The files in this directory preserve the unfinished online implementation from
Iteration 1, but use a `.dart.txt` suffix so Flutter analysis cannot compile or
validate it accidentally:

- `groups_api.dart.txt`
- `group_forms.dart.txt`
- `groups_page.dart.txt`

The online goal screen referenced by `groups_page.dart.txt` was not present in
the checkout. It was not fabricated. The shipped app routes the Groups action
to `GroupsUnavailablePage`, which states that this checkpoint is local-only.

Do not treat this archive as an implemented integration. Online setup,
account/session behavior, group membership, shared goals, and server-backed
progress remain deferred to later iterations.
