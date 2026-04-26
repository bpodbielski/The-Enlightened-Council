# The Enlightened Council

## A Suggested Evolution of the Multi-Model Council Concept

Strategic decisions are where careers, capital, and companies turn. Most people making those decisions today have a problem they did not have five years ago: an abundance of analytical horsepower with no shared method for using it well. Four frontier AI models, each capable of producing a credible analysis on any decision worth naming. The hard part is not generating the analysis. The hard part is knowing which analysis to trust.

A quiet research lineage has been forming around this problem. It started with a name most people in the space already know (Andrej Karpathy), picked up momentum through an adaptation that hit 1.3 million views (Ole Lehmann), and connects to a deeper body of academic work most practitioners have not yet read. This article walks the lineage piece by piece, then proposes an evolution that combines what each contribution gets right and adds two pieces the lineage has not yet integrated.

I am calling the evolution **The Enlightened Council**. The word choice is intentional. The premise is that AI does not reason for you. It surfaces angles you would otherwise miss. The reasoning stays where reasoning belongs: with the human running the decision.

---

## The origin: Karpathy's LLM Council

In November 2025, Andrej Karpathy released the LLM Council. The mechanism is elegant. Send the same question to four different frontier models in parallel. Each model responds independently. Each model then receives the others' responses anonymized and writes a peer review. A chairman model synthesizes the final verdict.

The contribution is real. Different models have different training data, different architectures, and different alignment regimes. They do not share blind spots. Routing one question through four of them surfaces angles any single model would suppress.

Karpathy noticed something in his own testing that maps to a deeper truth in this work. The models consistently praised GPT-5.1 as the most insightful, but he personally preferred Gemini's condensed output. The models disagreed with the human. The human disagreed with the models. The tension between machine consensus and human judgment is precisely where the value lives.

Source: https://github.com/karpathy/llm-council

---

## The adaptation: Lehmann's persona-based Council

Ole Lehmann rebuilt the Council inside a single Claude session as five sub-agent personas: the Contrarian, the First Principles Thinker, the Expansionist, the Outsider, and the Executor. Each advisor responds. Anonymous peer review. Chairman synthesizes.

The trade was clear. Multi-model diversity gave way to customizable analytical lenses you select per question. For fast brainstorming, the trade was worth making. The article reached 1.3 million views and put the Council framework in front of a much broader audience than the original ever reached.

What Lehmann added that Karpathy did not have: the framework bends to the decision domain, not the other way around. A founder needs different lenses than a content creator. An investor needs different lenses than an operator. The lens layer made the framework personal in a way the original was not.

---

## The diversity research: Stanford's Verbalized Sampling

Jiayi Zhang, Christopher Manning, and colleagues at Stanford published the Verbalized Sampling paper in October 2025. Their finding is sharp.

Aligned LLMs suffer mode collapse after RLHF. They converge on the most typical answer because the training process rewards stylistic familiarity. The tail of the distribution, where the non-obvious insights live, gets suppressed.

Their solution is deceptively simple. Ask the model to generate multiple candidate responses, then sample from the tails. Their published results show a 1.6 to 2.1x diversity improvement on creative tasks while quality holds steady.

The paper is important. The popular implementations of the technique take a shortcut the paper itself does not. Asking the model to label its own probabilities and pick the lowest produces the model's guess at what tail behavior looks like, not real distributional sampling. Faithful implementations need N independent samples at varied temperature with semantic clustering on the output. The outliers in the cluster are the actual tail.

Source: https://arxiv.org/abs/2510.01171

---

## The bias research: self-preference in LLM judges

Three peer-reviewed papers document the same phenomenon from different angles.

- **NeurIPS 2024** ("LLM Evaluators Recognize and Favor Their Own Generations") shows linear correlation between a model's ability to recognize its own output and the strength of its self-preference.
- **ICLR 2025** ("Self-Preference Bias in LLM-as-a-Judge") identifies the mechanism. Models score outputs stylistically familiar to themselves higher, where familiarity is measured by perplexity.
- **arXiv 2026** ("Self-Preference Bias in Rubric-Based Evaluation") shows the bias persists even with entirely objective grading criteria. Judges were up to 50 percent more likely to incorrectly mark outputs as correct when the output was their own.

The implication for any single-model peer review is unavoidable. A chairman model picking among four candidate verdicts is not picking the best verdict. It is picking the verdict most stylistically familiar to itself. Routing to four models then collapsing through one synthesizer recreates the bias the multi-model approach was designed to address.

---

## What each contribution gets right

Walking back through the lineage:

- **Karpathy.** Real model diversity matters. Different training, different architectures, different alignment regimes. Different blind spots.
- **Lehmann.** Customizable analytical lenses matter. The framework needs to bend to the decision domain.
- **Verbalized Sampling.** Mode collapse is a real problem. Tail-distribution insights are suppressed by default. Diversity must be designed in, not assumed.
- **Self-preference bias research.** Any single-model judge introduces systematic bias that compounds at the synthesis step. A multi-model panel that funnels through a single chairman loses what made the multi-model approach valuable in the first place.

Each piece is correct in what it adds. None of them, on their own, is sufficient.

---

## The Enlightened Council: a proposed evolution

The Enlightened Council combines what each prior work contributes, applies the constraints the research demands, and adds two pieces the lineage has not yet integrated. It is being built as a native macOS app for personal use.

**From Karpathy.** Real model diversity. The frontier panel runs Claude Opus, GPT, Gemini, and Grok in parallel. A balanced set is available for lower-stakes work. The peer-review step extends into three rounds of structured debate. Round 1 independent analysis. Round 2 anonymous rebuttal. Round 3 defend or update with explicit change flagging.

**From Lehmann.** Customizable analytical lenses. Eight curated lens templates per decision archetype (capital allocation, market entry, pivot or kill, vendor selection, org design, and more). Ten curated personas drawn from the lineage of thinking styles he popularized.

**From Stanford's Verbalized Sampling.** Real distributional sampling. N independent samples per persona at varied temperature with semantic clustering on the output. The outliers in the cluster are the actual tail, not whatever the model self-reports.

**From the bias research.** No single model gets the casting vote. The chairman pattern gets dropped. A force-directed argument graph renders every claim from every model and persona, exposing convergence and divergence directly. You drag nodes into a verdict tray and write the verdict yourself. AI generates and argues. The human reasons.

---

## The two missing pieces

Even with all six contributions integrated, the lineage misses two pieces that turn an analytical aid into a decision system.

### 1. A calibration ledger

Every verdict logs with confidence and a 60-day outcome deadline. The app prompts the user on the deadline date to mark what happened. Right, partial, or wrong. Notes on what changed. Over months and years, patterns surface.

- Which lens templates produced high-confidence verdicts that proved right.
- Which model panels produced verdicts the user later regretted.
- Which personas most influenced the final synthesis.

Decision tooling without an outcome loop is a thinking aid. Decision tooling with an outcome loop is a decision system. The difference is everything. None of the prior work in this lineage closes that loop.

### 2. Air gap mode

Strategic, financial, and personnel decisions touch information that does not belong in cloud APIs. The full Council framework needs to run on local hardware for sensitive work. Qwen 2.5 32B and Mistral Small 22B run sequentially on Apple Silicon. Zero cloud calls. Same lens templates. Same persona library. Same three-round debate. Same visual synthesis map. Private.

---

## Three layers of diversity, one human at the center

The unique stack is three layers of diversity working at once:

- **Between-model.** Different training lineages produce different blind spots.
- **Within-model.** Real distributional sampling surfaces the suppressed tail.
- **Analytical.** Custom lenses for your decision domain focus the output where it matters.

With a human at the center doing what humans do best under uncertainty: iterative synthesis.

---

## The premise behind the project

Most AI tools want to give you the answer. The lineage I am building on argues the opposite. Reasoning is iterative. AI is best understood as a system of components. The answer is yours to make. The AI exists to ensure you have considered every angle worth considering.

That is what the word "enlightened" is doing in the title. The point is not the verdict. The point is what you see along the way. A council that hands you a verdict gives you less than the framework can offer. A council that helps you see what you would have missed has done its job.

---

## Two open questions for anyone working in this space

1. When AI generates and argues, who is doing the reasoning? A single model? An ensemble? Or the human?

2. What does an outcome loop look like for AI-assisted decision making, and why has the lineage not yet built one?

I am building The Enlightened Council as a personal Mac app for my own strategic work. The PRD, build plan, and implementation spec are written. The first phase is in progress. If the framework lands for you, I would value the conversation.

---

## References

- Karpathy, A. (2025). *LLM Council.* https://github.com/karpathy/llm-council
- Lehmann, O. (2025). *The LLM Council Skill for Claude.* (1.3M views, source article)
- Zhang, J., Manning, C., et al. (2025, October). *Verbalized Sampling.* https://arxiv.org/abs/2510.01171
- Panickssery, A., et al. (2024). *LLM Evaluators Recognize and Favor Their Own Generations.* NeurIPS 2024. https://arxiv.org/abs/2404.13076
- Wataoka, K., et al. (2025). *Self-Preference Bias in LLM-as-a-Judge.* ICLR 2025. https://arxiv.org/abs/2410.21819
- *Self-Preference Bias in Rubric-Based Evaluation.* arXiv 2026. https://arxiv.org/abs/2604.06996

---
