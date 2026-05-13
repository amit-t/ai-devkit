# foo — context

This is a minimal mock CONTEXT.md used by `tests/test-wb-context-scan-*`
to stand in for what the `repo-context-scan` skill would actually produce.

## Domain concepts

- **Payment** — represents a charge attempt against a card or bank account.
- **Invoice** — a billable record produced for a customer over a period.
- **Refund** — reverses a prior **Payment** for some amount.
- **CustomerId** — opaque identifier used to associate **Payment** events
  with a customer entity.

## Notes

Concept extraction should de-duplicate (so **Payment** only counts once)
and stop at three terms.
