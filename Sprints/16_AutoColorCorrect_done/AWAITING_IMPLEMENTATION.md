# Awaiting Implementation

## Follow-on (v2+) Enhancements
- **White Balance**: Improve beyond neutral heuristic.
- **Advanced exposure**: Add histogram-based highlight/shadow constraints.
- **Shot matching**: Add consistency checks across shots.

## Technical Debt
- **Simple Heuristics**: "Mean luma" is too simple for production grade exposure correction.

## Recommendations
- Implement Histogram-based limits.
- Implement White Balance estimation.
