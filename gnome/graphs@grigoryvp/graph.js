// Bar graphs drawn the same way as hammerspoon/menuitem.lua does

export const GREEN = [0, 1, 0];
export const YELLOW = [1, 1, 0];
export const ORANGE = [1, 0.5, 0];
export const RED = [1, 0, 0];
export const GREY = [0.5, 0.5, 0.5];

export const BAR_WIDTH = 2;

// Bar for a value by [upper limit, color] ranges: each range takes an equal
// part of the height, so small values are still visible. null for a value
// beyond the last range.
export function scaled(value, ranges) {
  let low = 0;
  for (const [i, [high, color]] of ranges.entries()) {
    if (value < high) {
      return {val: ((value - low) / (high - low) + i) / ranges.length, color};
    }
    low = high;
  }
  return null;
}

// Bars are {val: 0..1, color}, newest first, drawn from the left
export function draw(area, bars) {
  const cr = area.get_context();
  const [width, height] = area.get_surface_size();
  cr.setSourceRGB(0, 0, 0);
  cr.rectangle(0, 0, width, height);
  cr.fill();
  cr.setSourceRGB(...GREY);
  cr.setLineWidth(1);
  cr.rectangle(0.5, 0.5, width - 1, height - 1);
  cr.stroke();
  for (const [i, {val, color}] of bars.entries()) {
    // Whole pixels: a fractional top is drawn blurred
    const barHeight = Math.round(
      Math.min(Math.max(val * (height - 2), 2), height - 2));
    cr.setSourceRGB(...color);
    cr.rectangle(1 + i * BAR_WIDTH, height - 1 - barHeight,
      BAR_WIDTH, barHeight);
    cr.fill();
  }
  cr.$dispose();
}
