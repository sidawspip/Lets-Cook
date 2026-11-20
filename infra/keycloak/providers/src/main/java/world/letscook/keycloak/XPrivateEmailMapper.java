package world.letscook.keycloak;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Collections;
import java.util.List;

import org.keycloak.broker.provider.AbstractIdentityProviderMapper;
import org.keycloak.broker.provider.BrokeredIdentityContext;
import org.keycloak.models.IdentityProviderMapperModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;
import org.keycloak.provider.ProviderConfigProperty;

/** Supplies an internal email only when an OAuth identity does not provide one. */
public final class XPrivateEmailMapper extends AbstractIdentityProviderMapper {
    public static final String PROVIDER_ID = "lets-cook-x-private-email";

    @Override
    public String[] getCompatibleProviders() {
        return new String[] { "oauth2" };
    }

    @Override
    public String getDisplayCategory() {
        return "Attribute Importer";
    }

    @Override
    public String getDisplayType() {
        return "Let's Cook X private email";
    }

    @Override
    public String getHelpText() {
        return "Creates a stable internal email from the broker user ID when X does not return an email.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return Collections.emptyList();
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    public void preprocessFederatedIdentity(
            KeycloakSession session,
            RealmModel realm,
            IdentityProviderMapperModel mapperModel,
            BrokeredIdentityContext context) {
        ensureEmail(context);
    }

    @Override
    public void importNewUser(
            KeycloakSession session,
            RealmModel realm,
            UserModel user,
            IdentityProviderMapperModel mapperModel,
            BrokeredIdentityContext context) {
        copyEmailToUser(user, context);
    }

    @Override
    public void updateBrokeredUser(
            KeycloakSession session,
            RealmModel realm,
            UserModel user,
            IdentityProviderMapperModel mapperModel,
            BrokeredIdentityContext context) {
        copyEmailToUser(user, context);
    }

    @Override
    public void updateBrokeredUserLegacy(
            KeycloakSession session,
            RealmModel realm,
            UserModel user,
            IdentityProviderMapperModel mapperModel,
            BrokeredIdentityContext context) {
        copyEmailToUser(user, context);
    }

    private static void copyEmailToUser(UserModel user, BrokeredIdentityContext context) {
        ensureEmail(context);
        if (user.getEmail() == null || user.getEmail().isBlank()) {
            user.setEmail(context.getEmail());
        }
    }

    private static void ensureEmail(BrokeredIdentityContext context) {
        if (context.getEmail() != null && !context.getEmail().isBlank()) {
            return;
        }

        String externalId = context.getId();
        if (externalId == null || externalId.isBlank()) {
            externalId = context.getBrokerUserId();
        }
        if (externalId == null || externalId.isBlank()) {
            throw new IllegalStateException("X did not return a stable user identifier");
        }

        context.setEmail("x-" + shortHash(externalId) + "@identity.xynk.in");
    }

    private static String shortHash(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder result = new StringBuilder(24);
            for (int index = 0; index < 12; index++) {
                result.append(String.format("%02x", digest[index]));
            }
            return result.toString();
        } catch (NoSuchAlgorithmException exception) {
            throw new IllegalStateException("SHA-256 is unavailable", exception);
        }
    }
}
