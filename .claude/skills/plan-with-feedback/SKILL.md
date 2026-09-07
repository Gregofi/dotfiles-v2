---
name: plan-with-feedback
description: Plan iteratively into a file. Read and react to feedback from the user directly into the file.
disable-model-invocation: true
metadata:
    author: "Filip Gregor"
    version: "1"
---

# Planning

We will plan a feature using a file.
Everything about the plan will be written into `PLAN.md`.

The point of planning into a file is that, contrary to normal _Plan Mode_, the user can offer a way better feedback:

- He can write feedback directly at a place that is concerning
- When you update the plan, he can view the diff that happened, instead of reviewing the whole plan

`PLAN.md` is deleted by the user manually once it is no longer needed.

## Scope

This is planning only.
`PLAN.md` is the only file you may create or modify.
Do not implement any part of the plan and do not run commands that change state.
Reading and searching the repository is expected, and needed to plan well.

## Format

Use the following structure in the plan:

```markdown
# <feature>

## Abstract

Why we are doing this and what it gets us. A few sentences, product level, no implementation detail.

## Architecture

High level overview of what changes, and why that shape.

## Changes

What we need to touch, at the level of behaviour rather than lines.
For example, file X exposes function Y, which is called across Z, W, Q.

## Steps

- [ ] 1. <smallest change that stands on its own>
- [ ] 2. <next one, building on the first>

## Out of scope

What we are deliberately not doing in this round.
```

Each step must be small enough to implement and verify on its own.
Mark a step `- [x]` only once it is done.

## Comment threads

Threads work like comments on a pull request.
Depth marks who spoke: `>` the user, `>> C:` you, `>>>` the user, and so on.

The user comments like this:

```
We will have to update X, because the Y file includes it.

> Yes, but for now, lets not update tests.
```

Act on a thread only when its deepest line is `U:`.
A thread whose deepest line is `C:` waits on the user. Leave it alone.
Never edit or delete a thread.
The user closes it by deleting it.

For each thread you act on, change the plan if the comment calls for it,
then append one reply at the next depth stating what changed and why.
Keep it at few sentences, be terse.

```
We will have to update X, because the Y file includes it.

> Yes, but for now, lets not update tests.
>> Claude:
>> Tests themselves won't be updated.
>> But the imports in tests have to be fixed, due to different function names.
```

You may open a thread with `> Claude:` to raise an open question.
The `> Claude:` must not contain any text after.
Put the actual message on a new line (as seen in the example).

Example of longer conversation:
```
> Lorem ipsum dolor sit amet.
>> Claude:
>> Lorem ipsum dolor sit amet.
>> Lorem ipsum dolor sit amet.
>>> Lorem ipsum dolor sit amet.
>>>> Claude:
>>>> Lorem ipsum dolor sit amet.
```

Never change the plan itself based on user comment, when you agree with something, write an acknowledgemnt message.
The user will then respond to you, prompting you to either do this or not.

## Rounds

The user edits `PLAN.md` outside the conversation.
Re-read it from disk at the start of every round, before anything else.
The user will write simple `go` to the prompt when he responded or added new conversations.
