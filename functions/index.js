const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

admin.initializeApp();

const GEN_AI_KEY = functions.config().gemini.key;

exports.generateTravelPhoto = functions.firestore
  .document("users/{userId}/photos/{photoId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const { userId, photoId } = context.params;

    if (data.status !== "pending") return;

    try {
      console.log(`Processing photo ${photoId} for user ${userId}...`);

      if (!GEN_AI_KEY) {
        throw new Error("Gemini API Key not set.");
      }

      const genAI = new GoogleGenerativeAI(GEN_AI_KEY);
      const model = genAI.getGenerativeModel({ model: "gemini-2.5-flash" });

      // 1. Generate Prompt with Gemini (text only)
      const promptResult = await model.generateContent([
        "Generate a short, vivid image generation prompt for a travel photo of a person. Example: 'A smiling woman standing on a beach in Bali at sunset'. Output ONLY the prompt."
      ]);
      const promptResponse = await promptResult.response;
      const aiPrompt = promptResponse.text().trim();
      console.log("Gemini generated prompt:", aiPrompt);

      // Encode prompt for URLs
      const encodedPrompt = encodeURIComponent(aiPrompt);
      let generatedUrl;

      try {
        // 2a. Try NanoBanana first (test by actually fetching)
        const nanoResponse = await fetch(
          `https://api.nanobanana.com/v1/i?text=${encodedPrompt}&model=flux&width=1024&height=1024`,
          { method: 'HEAD', timeout: 5000 }
        );

        if (nanoResponse.ok) {
          generatedUrl = nanoResponse.url;
          console.log("✅ NanoBanana success");
        } else {
          throw new Error(`NanoBanana failed: ${nanoResponse.status}`);
        }
      } catch (nanoError) {
        console.log("❌ NanoBanana failed, using Pollinations:", nanoError.message);
        // 2b. Fallback to Pollinations
        generatedUrl = `https://image.pollinations.ai/prompt/${encodedPrompt}`;
      }

      // 3. Update Firestore
      await snap.ref.update({
        status: "completed",
        generatedUrl: generatedUrl,
        aiDescription: aiPrompt,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log("✅ Photo generation successful! URL:", generatedUrl);

    } catch (error) {
      console.error("❌ Error generating photo:", error);
      await snap.ref.update({
        status: "failed",
        error: error.message,
      });
    }
  });
