# Branch workflow for testing multiplayer fixes

This repository now includes a helper branch for validating the high-level multiplayer setup before pushing changes.

## Create and switch to the test branch
The repository already contains a `master` reference. To work on the dedicated branch based on `master`, use:

```bash
git checkout master
git checkout -b multiplayer-fix
```

If the branch already exists locally, just switch to it:

```bash
git checkout multiplayer-fix
```

## Pull latest updates from `master`
Before testing or committing, make sure your branch matches the latest `master` state:

```bash
git checkout master
git pull origin master
# Update the feature branch
git checkout multiplayer-fix
git rebase master
```

If rebasing is not desired, you can merge instead:

```bash
git checkout multiplayer-fix
git merge master
```

## Push the branch for review
Once your tests in Godot 4.5.1 look good, push the branch to share it:

```bash
git push -u origin multiplayer-fix
```

After review, you can open a pull request targeting `master` and merge it when approved.
