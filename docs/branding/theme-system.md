PlanDone Theme System
Overview

PlanDone ships with three curated themes that users can select from.

The goal of the theme system is to:

Provide personalization without complexity

Maintain clean visual consistency across the app

Preserve accessibility and readability

Support offline-first architecture

Keep branding cohesive while allowing user expression

Themes are purely visual and do not affect behavior, data, or sync logic.

Design Philosophy

PlanDone is designed to feel:

Calm

Structured

Focused

Modern

Consumer-friendly

Not enterprise-heavy

All themes share the same semantic color roles. Only the palette changes.

This ensures:

UI consistency

Minimal design debt

Easy expansion (dark mode, custom accents later)

Scalable theming architecture

Theme Architecture

Each theme defines the following semantic roles:

primary

secondary

accent (success / done state)

warning (overdue)

background

surface

textPrimary

textSecondary

UI components must reference semantic roles — not hard-coded colors.

Example:

Done column → accent

Overdue date → warning

AppBar → primary

Card background → surface

This prevents theme leakage and keeps the system scalable.

Theme 1 — Calm Focus (Default)
Description

Calm Focus is the default PlanDone theme.

It emphasizes clarity, trust, and structure.
It is designed for deep work and long productivity sessions.

This theme represents the core brand identity of PlanDone.

Emotional Tone

Structured

Reliable

Calm

Intelligent

Professional without being corporate

Color Palette

Primary: #2E3A59
Secondary: #4F6BED
Accent (Done): #3DBE7A
Warning (Overdue): #F5A623
Background: #F7F9FC
Surface: #FFFFFF
Text Primary: #1C1C1E
Text Secondary: #6B7280

Usage Notes

Default theme on first install

Used in marketing screenshots

Recommended for most users

Works best for long productivity sessions

Theme 2 — Modern Minimal
Description

Modern Minimal is built for users who prefer a sharper, cleaner, more technical aesthetic.

It reduces visual noise and emphasizes contrast and clarity.

Ideal for power users and developers.

Emotional Tone

Crisp

Focused

Efficient

Minimal

Slightly technical

Color Palette

Primary: #1F1F1F
Secondary: #5A5A5A
Accent: #00C2A8
Warning: #FFB020
Background: #FFFFFF
Surface: #F4F4F4
Text Primary: #111111
Text Secondary: #666666

Usage Notes

Appeals to productivity enthusiasts

High visual clarity

Easily extendable to dark mode variant

Theme 3 — Warm Momentum
Description

Warm Momentum introduces a more human and approachable tone.

It softens the productivity experience and makes PlanDone feel less like a “work tool” and more like a life organizer.

Ideal for personal planning and lifestyle organization.

Emotional Tone

Friendly

Encouraging

Approachable

Slightly playful

Energetic without being loud

Color Palette

Primary: #223046
Secondary: #F76C5E
Accent: #4DD4AC
Warning: #FF9F43
Background: #FAF8F6
Surface: #FFFFFF
Text Primary: #1C1C1E
Text Secondary: #7A7A7A

Usage Notes

Good for personal boards

Makes onboarding feel warmer

Distinguishes PlanDone from enterprise tools

Theme Persistence

Theme selection is:

Stored locally in the app database (Drift or Isar)

Managed through Riverpod

Applied at the MaterialApp level

Offline-first

Not synced to backend in v1

Theme flow:

UI → State → Repository → Local DB
App startup reads theme → Riverpod provider exposes ThemeData → MaterialApp rebuilds

Accessibility Guidelines

All themes must:

Maintain sufficient contrast ratios

Keep text readable on background and surface

Avoid color-only state indicators (icons + color together)

Support colorblind-friendly usage

Status indicators (e.g., overdue, completed) must not rely on color alone.

Future Expansion

The theme system is designed to support:

Dark mode variants

Custom accent color selection

High contrast accessibility mode

AI-suggested theme preferences

Syncing theme per user account (future SaaS)

Brand Alignment

PlanDone branding principles:

Structured calm

Clear progress

Quiet confidence

Human-centered productivity

AI-enhanced, not AI-branded

Themes must reinforce these principles.