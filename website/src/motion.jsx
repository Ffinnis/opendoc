"use client";

import gsap from "gsap";
import { ScrollTrigger } from "gsap/ScrollTrigger";
import { useGSAP } from "@gsap/react";

gsap.registerPlugin(ScrollTrigger, useGSAP);

// One scoped controller owns scroll motion. MatchMedia reverts every tween and
// trigger when motion is paused, the viewport changes, or the page unmounts.
export default function PageMotion({ scope, paused }) {
  useGSAP(
    () => {
      if (paused) return;
      const media = gsap.matchMedia();
      media.add(
        {
          normal: "(prefers-reduced-motion: no-preference)",
          desktop: "(min-width: 768px)",
        },
        ({ conditions }) => {
          if (!conditions.normal) return;
          const select = gsap.utils.selector(scope);
          const entrance = gsap.timeline({
            defaults: { ease: "power3.out", duration: 1 },
          });
          entrance
            .from(select(".hero-title-line"), {
              y: 28,
              stagger: 0.12,
              clearProps: "transform",
            })
            .from(
              select(".hero-copy > p, .hero-actions"),
              { y: 16, stagger: 0.1, clearProps: "transform" },
              0.15,
            )
            .from(
              select(".hero-dock-wrap .dock-scroll"),
              { y: 42, scale: 0.96, clearProps: "transform" },
              0.2,
            );

          select("[data-reveal]").forEach((element) => {
            gsap.from(element, {
              y: 32,
              duration: 0.95,
              ease: "power3.out",
              clearProps: "transform",
              scrollTrigger: { trigger: element, start: "top 92%", once: true },
            });
          });
          select("[data-scrub-text]").forEach((element) => {
            gsap.fromTo(
              element.querySelectorAll(".scrub-word"),
              { "--highlight": "0%" },
              {
                "--highlight": "100%",
                stagger: 0.12,
                ease: "none",
                scrollTrigger: {
                  trigger: element,
                  start: "top 88%",
                  end: "bottom 65%",
                  scrub: 0.35,
                },
              },
            );
          });
          if (conditions.desktop) {
            gsap.to(select(".hero-backdrop img"), {
              yPercent: 12,
              ease: "none",
              scrollTrigger: {
                trigger: select(".hero")[0],
                start: "top top",
                end: "bottom top",
                scrub: true,
              },
            });
            const cards = select(".live-widget");
            cards.forEach((card, i) => {
              gsap.from(card, {
                x: () => (1 - i) * (card.offsetWidth + 18),
                y: (i + 1) * 28,
                rotation: (i - 1) * 5,
                scale: 0.86,
                ease: "none",
                scrollTrigger: {
                  trigger: select(".widget-stage")[0],
                  start: "top 100%",
                  end: "top 65%",
                  scrub: 0.45,
                  invalidateOnRefresh: true,
                },
              });
            });
            gsap.from(select(".appearance-image img"), {
              scale: 0.92,
              rotation: 2,
              ease: "none",
              scrollTrigger: {
                trigger: select(".appearance")[0],
                start: "top 85%",
                end: "center 65%",
                scrub: 0.45,
              },
            });
          }
          // Loading fonts can change line wrapping. Refresh only after layout settles.
          let alive = true;
          document.fonts.ready.then(() => {
            if (alive) ScrollTrigger.refresh();
          });
          scope.current.dataset.motionReady = "true";
          return () => {
            alive = false;
            delete scope.current?.dataset.motionReady;
          };
        },
        scope,
      );
      return () => media.revert();
    },
    { scope, dependencies: [paused], revertOnUpdate: true },
  );
  return null;
}
