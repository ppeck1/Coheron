# Coheron

**Coheron** is a local-first personal observability system designed to model human state as a structured, multi-domain system and visualize coherence over time.

It treats behavior, environment, and output not as isolated metrics—but as an interconnected system with measurable patterns, drift, and stability.

---

## Overview

Most self-tracking tools reduce complex human systems into flat metrics (steps, mood scores, time logs). This creates dimensional collapse—where important structure is lost.

Coheron approaches this differently:

- Models state across three domains  
- Preserves structure through hierarchical decomposition  
- Tracks change over time  
- Visualizes patterns as fields, not just numbers  

---

## Core Model

### Domains
- Internal — physiological and psychological state  
- External — environment and constraints  
- Output — behavior and actions  

### Planes → Indicators

INTERNAL  
Rest / Pain / Energy  
Focus / Overwhelm / Noise  
Anxiety / Mood / Drive  

EXTERNAL  
Safety / Noise / Barriers  
Support / Conflict / Demands  
Money / Time / Capacity  

OUTPUT  
Follow-through / Reactivity / Drift  
Activity / Intake / Rhythm  
Recovery / Soothing / Release  

---

## Key Features

- Structured input system (in progress)  
- Atlas visualization (Gaussian / density / contour)  
- Time-series tracking  
- Local-first architecture  

---

## Architecture

Flutter frontend  
Domain → Plane → Indicator model  
Aggregation + delta + visualization pipeline  

---

## Current State

Working:
- Core taxonomy  
- Partial input + visualization  
- APK builds  

Issues:
- Input UI bugs  
- Persistence inconsistencies  
- Visualization overlap  

---

## Getting Started

```bash
flutter pub get
flutter run
```

---

## License

MIT License

---

## Author

Paul Peck

