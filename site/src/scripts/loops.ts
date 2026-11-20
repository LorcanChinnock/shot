// Holds every looping clip (video.loop) on its poster when the viewer asks for less motion, and loads and plays each
// clip only while it's near the window. Used by Loop.astro and by the guide, whose GIFs play as these clips.
const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
const seen = new IntersectionObserver((entries) => {
  for (const entry of entries) {
    const video = entry.target as HTMLVideoElement;
    if (entry.isIntersecting) {
      if (reduce) continue;
      if (video.preload === 'none') video.preload = 'auto';
      video.play().catch(() => {});
    } else {
      video.pause();
    }
  }
}, { rootMargin: '200px' });
for (const video of document.querySelectorAll<HTMLVideoElement>('video.loop')) {
  if (reduce) {
    video.removeAttribute('autoplay');
    video.pause();
    video.controls = true;
  }
  seen.observe(video);
}
