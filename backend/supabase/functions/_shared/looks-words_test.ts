// deno test _shared/
// The second net for lines Aybik writes next to her photo: talk of bodies,
// faces, skin or weight, or rating looks, in the app's languages, is caught;
// ordinary vibe words aren't.
import assert from "node:assert/strict";
import { talksAboutLooks } from "./looks-words.ts";

Deno.test("talk of bodies, faces, skin, weight or rating looks is caught", () => {
  for (
    const text of [
      "Who looks prettier?",
      "Which one is HOTTER",
      "Skinny vibes only",
      "Rate it 9/10",
      "Ten out of 10",
      "Flawless skin day",
      "Hangisi daha zayıf gösteriyor?",
      "¿Cuál me hace ver más delgada?",
      "Qual deixa o corpo melhor?",
      "Laquelle est la plus mince ?",
      "Welches zeigt meinen Körper besser?",
      "Quale mi fa sembrare più magra?",
      "Где фигура лучше?",
      "Mana yang bikin aku kelihatan kurus?",
      "どっちが痩せて見える？",
      "어느 쪽이 더 날씬해 보여?",
      "哪张显得身材好？",
    ]
  ) assert.ok(talksAboutLooks(text), text);
});

Deno.test("ordinary vibe lines pass", () => {
  for (
    const text of [
      "Which vibe for Friday's party? 🎉",
      "Hot chocolate and rainy windows",
      "Golden hour, best hour",
      "Gros bisous de la plage",
      "Bugün hava çok güzel",
      "肌寒い秋の朝",
      "笑顔の週末",
      "웃는 얼굴로 주말 시작",
      "Pretty in pink",
      "A figurine on a shelf",
      "Ready in 5 to 10 minutes",
    ]
  ) assert.ok(!talksAboutLooks(text), text);
});
