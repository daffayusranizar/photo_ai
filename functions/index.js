const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { GoogleGenerativeAI } = require("@google/generative-ai");

admin.initializeApp();

const GEN_AI_KEY = functions.config().gemini.key;

async function imageUrlToBase64(url) {
  const fetch = (await import('node-fetch')).default;
  const response = await fetch(url);
  if (!response.ok) {
    throw new Error(`Failed to fetch image: ${response.status} ${response.statusText}`);
  }
  const buffer = Buffer.from(await response.arrayBuffer());
  return buffer.toString("base64");
}

exports.generateTravelPhoto = functions.firestore
  .document("users/{userId}/photos/{photoId}")
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const { userId, photoId } = context.params;

    if (data.status !== "pending") return;

    try {
      console.log(`🔄 Processing photo ${photoId} for user ${userId}`);

      const imageUrl = data.originalUrl;
      if (!imageUrl) {
        throw new Error("No originalUrl found in document");
      }

      // STEP 1: Convert original image to base64 for reference
      console.log("📸 Converting reference image...");
      const referenceImageBase64 = await imageUrlToBase64(imageUrl);

      // STEP 2: Analyze person appearance with Gemini (optional but helpful)
      console.log("👁️  Analyzing person with Gemini...");
      const genAI = new GoogleGenerativeAI(GEN_AI_KEY);
      const analyzeModel = genAI.getGenerativeModel({ model: "gemini-2.0-flash" });

      const analysisPrompt = `Analyze this selfie and provide a brief, clear description of the person in 1-2 sentences. Focus on: gender, approximate age, hair (color and style), and any distinctive features. Keep it concise for AI image generation.`;

      const analysisResult = await analyzeModel.generateContent([
        { inlineData: { mimeType: "image/jpeg", data: referenceImageBase64 } },
        { text: analysisPrompt }
      ]);

      const analysisResponse = await analysisResult.response;
      if (!analysisResponse.candidates || analysisResponse.candidates.length === 0) {
        throw new Error("Gemini analysis returned no candidates");
      }

      const personDescription = await analysisResponse.text();
      console.log("✅ Person description:", personDescription);

      // STEP 3: Pick random destination
      const destinations = [
        "relaxing on a pristine Bali beach at golden sunset with palm trees and turquoise water",
        "sitting at a charming Parisian cafe with the Eiffel Tower visible in the background",
        "standing in Tokyo's vibrant Shibuya crossing at night with colorful neon lights",
        "hiking in a beautiful Swiss Alps meadow with snow-capped mountains and wildflowers",
        "enjoying the view from a white Santorini terrace overlooking the Aegean sea",
        "on a NYC rooftop with the Manhattan skyline at golden hour"
      ];

      const randomDestination = destinations[Math.floor(Math.random() * destinations.length)];
      console.log("📍 Destination:", randomDestination);

      // STEP 4: Generate image using Imagen 3 Customization API
      console.log("🖼️  Generating image with Imagen 3 Customization...");

      const { GoogleAuth } = require('google-auth-library');
      const auth = new GoogleAuth({
        scopes: 'https://www.googleapis.com/auth/cloud-platform'
      });
      const client = await auth.getClient();
      const projectId = await auth.getProjectId();
      const accessToken = await client.getAccessToken();

      // Create prompt with reference to subject [1]
      const generatePrompt = `Create a photorealistic travel photograph of ${personDescription} [1] ${randomDestination}. Professional travel photography, natural lighting, vibrant colors, high quality. The person should be the main subject, clearly visible and naturally integrated into the scene.`;

      console.log("Calling Imagen 3 Customization API...");
      const fetch = (await import('node-fetch')).default;

      const imagenResponse = await fetch(
        `https://us-central1-aiplatform.googleapis.com/v1/projects/${projectId}/locations/us-central1/publishers/google/models/imagen-3.0-capability-001:predict`,
        {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${accessToken.token}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            instances: [{
              prompt: generatePrompt,
              referenceImages: [{
                referenceType: "REFERENCE_TYPE_SUBJECT",
                referenceId: 1,
                referenceImage: {
                  bytesBase64Encoded: referenceImageBase64
                },
                subjectImageConfig: {
                  subjectDescription: personDescription,
                  subjectType: "SUBJECT_TYPE_PERSON"
                }
              }]
            }],
            parameters: {
              sampleCount: 1,
              language: "en"
            }
          })
        }
      );

      if (!imagenResponse.ok) {
        const errorText = await imagenResponse.text();
        throw new Error(`Imagen Customization API error: ${imagenResponse.status} - ${errorText}`);
      }

      const imagenData = await imagenResponse.json();

      if (!imagenData.predictions || imagenData.predictions.length === 0) {
        throw new Error("Imagen returned no predictions");
      }

      const imageBase64Data = imagenData.predictions[0].bytesBase64Encoded;
      if (!imageBase64Data) {
        throw new Error("No image data in Imagen response");
      }

      const imageBuffer = Buffer.from(imageBase64Data, 'base64');
      console.log(`✅ Image generated (${imageBuffer.length} bytes)`);

      // STEP 5: Upload to Storage
      const bucket = admin.storage().bucket();
      const fileName = `generated/${userId}/${photoId}_travel.png`;
      const file = bucket.file(fileName);

      console.log("📤 Uploading to Storage...");
      await file.save(imageBuffer, { metadata: { contentType: "image/png" } });
      await file.makePublic();

      const publicUrl = `https://storage.googleapis.com/${bucket.name}/${fileName}`;

      // STEP 6: Update Firestore
      await snap.ref.update({
        status: "completed",
        generatedUrl: publicUrl,
        personDescription,
        destination: randomDestination,
        fullPrompt: generatePrompt,
        originalImageUrl: imageUrl,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log(`🎉 SUCCESS: ${publicUrl}`);

    } catch (error) {
      console.error("❌ ERROR:", error.message);

      await snap.ref.update({
        status: "failed",
        error: error.message,
      });
    }
  });
