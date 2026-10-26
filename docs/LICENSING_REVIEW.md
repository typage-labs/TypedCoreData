# Apache 2.0 preparation and provenance review

**26 October 2026 — proposed terms only; owner/rightsholder review pending.**
Do not publish this candidate until the responsible owner confirms the rights
to distribute all included material under the proposed terms. No Olvid SAS rights
clearance, ownership assignment, or infringement finding is asserted here.

## Prepared license and attribution

[LICENSE](../LICENSE) contains the official English Apache License 2.0 terms,
including its appendix, obtained from the
[Apache Software Foundation's official text](https://www.apache.org/licenses/LICENSE-2.0.txt).
Web extraction normalized whitespace; the terms and appendix placeholders are
unchanged. No additional conditions or project-specific ownership statements
were inserted into the license text.

Proposed project attribution **for owner review**, based on the original staged
authorship header and the stated TypageLib project identity:

```text
TypedCoreData — a TypageLib project
Copyright 2026 Sylvain Heraud and TypedCoreData contributors
```

The personal name is an attribution proposal, not an ownership conclusion.
Before applying it, confirm the spelling, the legal copyright holder(s), the
years, and whether any employment or assignment changes the correct attribution.
TypageLib has not been assumed to be a separate legal entity. If rights belong
elsewhere, replace this proposal with the confirmed holder's notice and preserve
every applicable third-party notice.

After clearance, an optional source header can pair the confirmed copyright
notice with `SPDX-License-Identifier: Apache-2.0`. No such grant was added to
production sources in this preparation. A final NOTICE file should contain only
confirmed project/third-party attribution; none was fabricated here. Apache's
[application guidance](https://www.apache.org/foundation/license-faq.html#Apply-My-Software)
describes how to apply the license and copyright notice to one's own software.

## Evidence reviewed and unresolved origin questions

Reviewed HEAD (`ccc8a44`), staged blobs, all current production files, tests,
compile/crash probes, scripts, experiments, README and design/verification docs.
No external Olvid implementation was fetched, inspected, or copied during this
preparation. No existing third-party copyright notice was removed. This is a
repository provenance inventory, not a legal similarity analysis.

| Material | Available evidence | Required owner decision |
| --- | --- | --- |
| Original supplied typed-ID sketch and staged `ManagedID.swift` | The request supplied the wrapper/protocol/`Self` pattern. The staged file identifies Sylvain Heraud and 25 October 2026. | Establish where that supplied expression came from and whether its author had rights to contribute it. |
| Obsolete staged `TypeSafeCoreData.swift` | Blob `979459a6b736420bac419ed533c171a4aad9893f`; header identifies Sylvain Heraud and 20 October 2026. Includes an earlier typed-ID wrapper/protocol/resolver. Absent from working tree; excluded from intended inventory. Index removal remains blocked by filesystem permissions. | Trace its origin and any relationship to the earlier Olvid SAS implementation. Excluding the file does not establish that the surviving code is independent. |
| Current `ManagedID.swift` and `NSManagedObjectContext+ManagedID.swift` | Preserve the same concept with stronger static relationships, metadata validation and checked resolution. | Review the initial contribution and any protected expression, employment obligations or assignments. A rewrite alone is insufficient evidence. |
| Remaining five production files, fixtures, tests and tooling | Developed in this workspace from native APIs and the documented study; no third-party implementation was introduced in this preparation. | Confirm contributor authority and provenance across earlier work, including generated or supplied material. Repository observations do not certify unseen history. |
| README, audit/study/review docs and research prototypes | Include native API signatures, technical explanations, source links and programmatic experiments. Research-only prototypes are outside SPM targets. | Include documentation, examples and research in the clearance scope; retain any required attribution if previously sourced material is identified. |
| Proposed Apache license text | Official license reproduced for review, not an implementation borrowed from an Apache project. | Approve applying these terms to the work only after authority is established. Do not attribute ownership of TypedCoreData to the ASF. |

The owner identified an earlier Olvid SAS project distributed under AGPLv3.
That fact alone does not prove this implementation incorporates protected
expression, and independent code cannot be established solely by saying it was
rewritten. If protected material was carried over, the owner must determine
whether separate written permission authorizes the proposed licensing or whether
the affected material must be replaced under an appropriate independent process.
Replacement also does not automatically resolve contractual obligations.
The [earlier review, L1](PRE_RELEASE_REVIEW.md#l1--p0-no-authorized-licensingprovenance-decision-is-available)
records the underlying concerns and primary legal references.

## Evidence needed before publication

1. Confirm the copyright holder(s), contribution authority and relevant
   employment/assignment obligations for the supplied, staged and surviving work.
2. Identify any Olvid or other third-party expression that requires permission,
   replacement, or retained notices. Record the disposition with the owner and,
   where appropriate, qualified counsel; keep confidential agreements outside the
   public repository and record only an approved public conclusion here.
3. Confirm Apache 2.0 is authorized for the final inventory, approve the final
   attribution, and retain all required notices. Do not treat the proposed LICENSE
   file as evidence that this review has happened.

**Status: unresolved release gate.** Licensing materials are ready for review;
publication is not authorized or recommended by this document.
