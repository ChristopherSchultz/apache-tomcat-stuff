package net.christopherschultz.tomcat.realm;

import java.security.GeneralSecurityException;

import org.apache.catalina.CredentialHandler;
import org.apache.catalina.realm.MessageDigestCredentialHandler;

/**
 * A {@link CredentialHandler} that adds a TOTP prefix to the user's
 * credentials. Logging-in requires the user to enter their TOTP
 * code from their authenticator app plus their usual password
 * (e.g. "123456mypassword").
 *
 * The user-specific TOTP seed is stored in the stored credential
 * and will be used to cross-check the input credentials. Users
 * with TOTP seeds will have a stored credential with a prefix
 * which defaults to "totp$" (without quotes).
 *
 * For example, if a user has the TOTP seed
 * <code>tomcattomcattomcattomcat</code> and password
 * <code>test</code>, then the user's SHA-256 stored credential could look
 * like this:
 * <code>totp$tomcattomcattomcattomcat$ecf8ed52844875893d6d4a757869d0b496ad359afa4c1c7352aee25ec22416b7$1$c1d306bded9e6a926b93f40145590a2f6e23d813648a902b701c6aba9d285f68</code>.
 *
 * For the iteration count <code>C=49792274</code> (see RFC 6238 for details
 * on what <code>C</code> means), the TOTP token is <code>490391</code>
 * and so the user would enter <code>490391test</code> as their password
 * in e.g. a FORM login form.
 *
 * Use of a delegate CredentialHandler (e.g. {@link MessageDigestCredentialHandler},
 * {@link SecretKeyCredentialHandler} is <em>highly recommended</em> as TOTP
 * only provides a single authentication factor.
 *
 * Configuration:
 *
 * &lt;CredentialHandler type="TOTPComposableCredentialHandler"
 *   TOTPPrefix="totp$"
 *   TOTPCodeLength="6"&gt;
 *   &lt;CredentialHandler type="o.a.c.realm.SecretKeyCredentialHandler" ... /&gt;
 * &lt;/CredentialHandler&gt;
 */
public class TOTPCredentialHandler
    implements CredentialHandler {
    private CredentialHandler delegate;
    private String totpPrefix = "totp$";
    private int totpTokenLength = 6;
    private int intervals = 3;

    public TOTPCredentialHandler(CredentialHandler ch) {
        delegate = ch;
    }

    public TOTPCredentialHandler() {
        this(null);
    }

    @Override
    public boolean matches(String inputCredentials, String storedCredentials) {
        // Only use TOTP if stored credentials are blessed with a TOTP seed
        if(storedCredentials.startsWith(totpPrefix))
        {
            int pos = storedCredentials.indexOf('$', totpPrefix.length());

            if(pos > 0) {
                String totpSeed = storedCredentials.substring(totpPrefix.length(), pos);
                String[] totpValidCodes = getTOTPValidCodes(totpSeed);

                for(int i=0; i<totpValidCodes.length; ++i) {
                    if(inputCredentials.startsWith(totpValidCodes[i])) {
                        // For parent call, remove the TOTP prefix and seed
                        storedCredentials = storedCredentials.substring(pos+1);
                        inputCredentials = inputCredentials.substring(totpTokenLength);

                        if(null != delegate)
                            return delegate.matches(inputCredentials, storedCredentials);
                        else
                            return true;
                    }
                }

                // TOTP does not match. waste time and return false anyway
                if(null != delegate) {
                    storedCredentials = storedCredentials.substring(pos+1);
                    inputCredentials = inputCredentials.substring(totpTokenLength);
                    delegate.matches(inputCredentials, storedCredentials);
                }

                return false;
            }
            else
                throw new IllegalStateException("Invalid stored credential");
        }
        else if(null != delegate)
            return delegate.matches(inputCredentials, storedCredentials);
        else
            return false;
    }

    @Override
    public String mutate(String inputCredentials) {
        return totpPrefix + "[seed goes here]" + "$" + delegate.mutate(inputCredentials);
    }

    private String[] getTOTPValidCodes(String seed)
    {
        try {
            TimeBasedOneTimePad totp = new TimeBasedOneTimePad();
            return totp.getTokens(seed, this.intervals);
        } catch (GeneralSecurityException gsa) {
            // TODO: Log error
            return new String[0];
        }
    }

    public void setCredentialHandler(CredentialHandler ch) {
        delegate = ch;
    }

    /**
     * Sets the TOTP prefix that is used to mark users' stored credentials
     * as having a TOTP seed embedded in them.
     *
     * @param totpPrefix The prefix to use. Default is <code>totp$</code>
     */
    public void setTOTPPrefix(String totpPrefix) {
        if(null == totpPrefix || 0 == totpPrefix.trim().length())
            throw new IllegalArgumentException("TOTP prefix length needs to be > 0");

        this.totpPrefix = totpPrefix;
    }

    /**
     * Sets the TOTP token length in characters.
     *
     * @param length The length of the TOTP codes to use. Default is 6
     *               characters.
     */
    public void setTOTPTokenLength(int length) {
        this.totpTokenLength = length;
    }

    /**
     * Sets the number of valid intervals that should be used to check TOTP
     * tokens. This allows for clock-skew between the client and server.
     * If this number is &gt; 1, this credential handler will allow tokens
     * that were valid one or more time-intervals into the past as well as
     * those that will be valid one or more time intervals into the future
     * (as the server reckons time).
     *
     * @param intervals The number of intervals to check, with the
     *                  current time interval being centered in the list
     *                  of valid tokens.
     */
    public void setValidIntervals(int intervals) {
        this.intervals = intervals;
    }

    // Quick and dirty test driver
    public static void main(String[] args) throws Exception
    {
        MessageDigestCredentialHandler mdch = new MessageDigestCredentialHandler();
        mdch.setAlgorithm("SHA-256");
        TOTPCredentialHandler totpch = new TOTPCredentialHandler(mdch);

        System.out.println(totpch.matches(args[0], args[1]) ? "match" : "no match");
    }
}
